#!/usr/bin/env python3
"""Normalize narrow Sky130 SDF records for VCS specify match.

By default this script preserves the original pathname-only behavior: it only
rewrites standalone A1N/A2N tokens to A1_N/A2_N in COND expressions inside
selected Sky130 HS inverted-input conditional cell families whose PDK Verilog
ports and specify blocks use A1_N/A2_N.

With --normalize-async-recrem, it also merges adjacent async
RECOVERY/HOLD records for dfrtp/dfstp reset/set release checks into the single
RECREM record form used by the matching PDK specify blocks. The merge preserves
both timing limits and does not add invented checks or arcs.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
import re
import sys


CELLTYPE_RE = re.compile(r'\(CELLTYPE\s+"([^"]+)"')
COND_RE = re.compile(r"\(\s*COND\b")
AFFECTED_CELL_RE = re.compile(
    r"^sky130_fd_sc_hs__(?:o2bb2ai|a2bb2oi|o2bb2a)_[0-9]+$"
)
ASYNC_CELL_RE = re.compile(r"^sky130_fd_sc_hs__(dfrtp|dfstp)_[0-9]+$")
ASYNC_PIN_BY_FAMILY = {
    "dfrtp": "RESET_B",
    "dfstp": "SET_B",
}
ASYNC_RECORD_RE = re.compile(
    r"^(\s*)\((RECOVERY|HOLD)\s+\(posedge\s+(RESET_B|SET_B)\)\s+"
    r"\(posedge\s+CLK\)\s+(\([^()]*\))\)\s*$"
)
TOKEN_MAP = (
    ("A1N", "A1_N", re.compile(r"(?<![A-Za-z0-9_])A1N(?![A-Za-z0-9_])")),
    ("A2N", "A2_N", re.compile(r"(?<![A-Za-z0-9_])A2N(?![A-Za-z0-9_])")),
)


@dataclass
class CellStats:
    cells_seen: int = 0
    changed_cells: int = 0
    changed_lines: int = 0
    a1n_rewrites: int = 0
    a2n_rewrites: int = 0
    async_recrem_cells: int = 0
    async_recrem_pairs: int = 0
    async_recovery_records: int = 0
    async_hold_records: int = 0


@dataclass
class AsyncRecord:
    indent: str
    kind: str
    pin: str
    limit: str
    newline: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rewrite A1N/A2N condition tokens in affected Sky130 SDF cells."
    )
    parser.add_argument("--input", required=True, type=Path, help="Original SDF file")
    parser.add_argument("--output", required=True, type=Path, help="Normalized SDF file")
    parser.add_argument("--report", required=True, type=Path, help="Mapping/count report")
    parser.add_argument(
        "--normalize-async-recrem",
        action="store_true",
        help=(
            "Merge adjacent dfrtp/dfstp async RECOVERY/HOLD records into "
            "RECREM records matching the PDK specify $recrem checks."
        ),
    )
    return parser.parse_args()


def normalize_line(line: str) -> tuple[str, int, int]:
    new_line = line
    counts: dict[str, int] = {}
    for old, new, pattern in TOKEN_MAP:
        new_line, count = pattern.subn(new, new_line)
        counts[old] = count
    return new_line, counts["A1N"], counts["A2N"]


def async_pin_for_celltype(celltype: str) -> str | None:
    match = ASYNC_CELL_RE.match(celltype)
    if not match:
        return None
    return ASYNC_PIN_BY_FAMILY[match.group(1)]


def match_async_record(line: str) -> AsyncRecord | None:
    newline = ""
    body = line
    if body.endswith("\n"):
        newline = "\n"
        body = body[:-1]
    match = ASYNC_RECORD_RE.match(body)
    if not match:
        return None
    return AsyncRecord(
        indent=match.group(1),
        kind=match.group(2),
        pin=match.group(3),
        limit=match.group(4),
        newline=newline,
    )


def normalize_sdf(
    input_path: Path, output_path: Path, normalize_async_recrem: bool = False
) -> tuple[dict[str, CellStats], int, int]:
    if input_path.resolve() == output_path.resolve():
        raise ValueError("output path must be different from input path")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    stats: dict[str, CellStats] = defaultdict(CellStats)
    current_celltype = ""
    current_cell_counted_changed = False
    current_cell_counted_async_changed = False
    in_cell = False
    cell_depth = 0
    total_lines = 0
    output_lines = 0
    pending_async_recovery: tuple[str, AsyncRecord, str] | None = None

    with input_path.open("r", encoding="utf-8", newline="") as src, output_path.open(
        "w", encoding="utf-8", newline=""
    ) as dst:
        def write_line(out_line: str) -> None:
            nonlocal output_lines
            dst.write(out_line)
            output_lines += 1

        def flush_pending_recovery() -> None:
            nonlocal pending_async_recovery
            if pending_async_recovery is not None:
                write_line(pending_async_recovery[2])
                pending_async_recovery = None

        for line in src:
            total_lines += 1

            stripped = line.lstrip()
            if not in_cell and stripped.startswith("(CELL"):
                flush_pending_recovery()
                in_cell = True
                cell_depth = 0
                current_celltype = ""
                current_cell_counted_changed = False
                current_cell_counted_async_changed = False

            match = CELLTYPE_RE.search(line)
            if match:
                flush_pending_recovery()
                current_celltype = match.group(1)
                if AFFECTED_CELL_RE.match(current_celltype):
                    stats[current_celltype].cells_seen += 1
                elif normalize_async_recrem and async_pin_for_celltype(current_celltype):
                    stats[current_celltype].cells_seen += 1

            out_line = line
            if (
                current_celltype
                and AFFECTED_CELL_RE.match(current_celltype)
                and COND_RE.search(line)
            ):
                out_line, a1_count, a2_count = normalize_line(line)
                if a1_count or a2_count:
                    cell_stats = stats[current_celltype]
                    cell_stats.changed_lines += 1
                    cell_stats.a1n_rewrites += a1_count
                    cell_stats.a2n_rewrites += a2_count
                    if not current_cell_counted_changed:
                        cell_stats.changed_cells += 1
                        current_cell_counted_changed = True

            handled_async = False
            if normalize_async_recrem:
                expected_pin = async_pin_for_celltype(current_celltype)
                async_record = match_async_record(out_line)
                if pending_async_recovery is not None:
                    pending_celltype, recovery_record, recovery_line = pending_async_recovery
                    if (
                        expected_pin
                        and pending_celltype == current_celltype
                        and async_record is not None
                        and async_record.kind == "HOLD"
                        and async_record.pin == recovery_record.pin
                        and async_record.pin == expected_pin
                    ):
                        merged_line = (
                            f"{recovery_record.indent}(RECREM "
                            f"(posedge {async_record.pin}) (posedge CLK) "
                            f"{recovery_record.limit} {async_record.limit})"
                            f"{async_record.newline or recovery_record.newline}"
                        )
                        write_line(merged_line)
                        cell_stats = stats[current_celltype]
                        cell_stats.async_recrem_pairs += 1
                        cell_stats.async_recovery_records += 1
                        cell_stats.async_hold_records += 1
                        if not current_cell_counted_async_changed:
                            cell_stats.async_recrem_cells += 1
                            current_cell_counted_async_changed = True
                        pending_async_recovery = None
                        handled_async = True
                    else:
                        write_line(recovery_line)
                        pending_async_recovery = None

                if not handled_async and expected_pin and async_record is not None:
                    if async_record.kind == "RECOVERY" and async_record.pin == expected_pin:
                        pending_async_recovery = (current_celltype, async_record, out_line)
                        handled_async = True

            if not handled_async:
                write_line(out_line)

            if in_cell:
                cell_depth += line.count("(") - line.count(")")
                if cell_depth <= 0:
                    flush_pending_recovery()
                    in_cell = False
                    current_celltype = ""
                    current_cell_counted_changed = False
                    current_cell_counted_async_changed = False

        flush_pending_recovery()

    return dict(stats), total_lines, output_lines


def write_report(
    report_path: Path,
    input_path: Path,
    output_path: Path,
    stats: dict[str, CellStats],
    total_lines: int,
    output_lines: int,
    normalize_async_recrem: bool,
) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    total_changed_lines = sum(s.changed_lines for s in stats.values())
    total_changed_cells = sum(s.changed_cells for s in stats.values())
    total_a1 = sum(s.a1n_rewrites for s in stats.values())
    total_a2 = sum(s.a2n_rewrites for s in stats.values())
    total_async_cells = sum(s.async_recrem_cells for s in stats.values())
    total_async_pairs = sum(s.async_recrem_pairs for s in stats.values())
    total_async_recovery = sum(s.async_recovery_records for s in stats.values())
    total_async_hold = sum(s.async_hold_records for s in stats.values())

    with report_path.open("w", encoding="utf-8", newline="\n") as report:
        report.write("Sky130 SDF pathname/condition-token normalization report\n")
        report.write(f"input: {input_path}\n")
        report.write(f"output: {output_path}\n")
        report.write("scope: affected CELLTYPE blocks matching ")
        report.write("sky130_fd_sc_hs__(o2bb2ai|a2bb2oi|o2bb2a)_[0-9]+\n")
        report.write("mapping: A1N -> A1_N, A2N -> A2_N in COND lines only\n")
        report.write("delay_values_changed: 0\n")
        report.write("instances_changed: 0\n")
        report.write("celltypes_changed: 0\n")
        report.write(f"input_lines: {total_lines}\n")
        if normalize_async_recrem:
            report.write(f"output_lines: {output_lines}\n")
        report.write(f"changed_cells: {total_changed_cells}\n")
        report.write(f"changed_lines: {total_changed_lines}\n")
        report.write(f"A1N_to_A1_N: {total_a1}\n")
        report.write(f"A2N_to_A2_N: {total_a2}\n")
        if normalize_async_recrem:
            report.write("\nasync_recrem_enabled: 1\n")
            report.write("async_recrem_scope: sky130_fd_sc_hs__dfrtp_[0-9]+ ")
            report.write("RESET_B and sky130_fd_sc_hs__dfstp_[0-9]+ SET_B\n")
            report.write("async_recrem_mapping: adjacent RECOVERY/HOLD -> RECREM\n")
            report.write("async_recrem_delay_values_changed: 0\n")
            report.write("async_recrem_instances_changed: 0\n")
            report.write("async_recrem_celltypes_changed: 0\n")
            report.write(f"async_recrem_cells: {total_async_cells}\n")
            report.write(f"async_recrem_pairs: {total_async_pairs}\n")
            report.write(f"async_recrem_recovery_records_merged: {total_async_recovery}\n")
            report.write(f"async_recrem_hold_records_merged: {total_async_hold}\n")
            report.write(f"timing_check_records_added: {total_async_pairs}\n")
            report.write(f"timing_check_records_removed: {total_async_pairs * 2}\n")
            report.write(f"timing_check_record_net_delta: {-total_async_pairs}\n")
        report.write("\nper_celltype:\n")
        if normalize_async_recrem:
            report.write(
                "celltype cells_seen changed_cells changed_lines A1N_to_A1_N "
                "A2N_to_A2_N async_recrem_cells async_recrem_pairs "
                "async_recovery_records async_hold_records\n"
            )
        else:
            report.write(
                "celltype cells_seen changed_cells changed_lines A1N_to_A1_N "
                "A2N_to_A2_N\n"
            )
        for celltype in sorted(stats):
            cell_stats = stats[celltype]
            base_report = (
                f"{celltype} {cell_stats.cells_seen} {cell_stats.changed_cells} "
                f"{cell_stats.changed_lines} {cell_stats.a1n_rewrites} "
                f"{cell_stats.a2n_rewrites}"
            )
            if normalize_async_recrem:
                report.write(
                    f"{base_report} {cell_stats.async_recrem_cells} "
                    f"{cell_stats.async_recrem_pairs} "
                    f"{cell_stats.async_recovery_records} "
                    f"{cell_stats.async_hold_records}\n"
                )
            else:
                report.write(f"{base_report}\n")


def main() -> int:
    args = parse_args()
    try:
        stats, total_lines, output_lines = normalize_sdf(
            args.input, args.output, args.normalize_async_recrem
        )
        write_report(
            args.report,
            args.input,
            args.output,
            stats,
            total_lines,
            output_lines,
            args.normalize_async_recrem,
        )
    except Exception as exc:  # pragma: no cover - surfaced to shell caller
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
