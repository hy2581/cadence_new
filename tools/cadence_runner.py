#!/usr/bin/env python3
"""
cadence_runner.py — fully-automated driver for Cadence CPIPC Cloud (cpipc.cadencecloud.cn)

Subcommands:
    login                 ensure logged in, persist session state
    open                  log in then keep browser headed for manual inspection (debug)
    list                  list files in the room's FILES tab
    upload <path>         upload a file via the Files page (set_input_files, no OS picker)
    download <name> [out] download a file from the Files page
    probe                 print what is reachable inside the App Presenter iframe (noVNC)
    run [task]            package submission/, upload, trigger, wait, fetch results
    status                quick health check (cookies valid? room online?)

Design notes:
- Uses sync Playwright with persistent storage_state so we re-use the Keycloak SSO session
- The Cadence portal hides the file <input type="file"> behind a green Upload button.
  We bypass the OS file picker by calling locator.set_input_files() directly.
- Mate Desktop is a cross-origin iframe (title="App Presenter"). The probe command
  inspects whether we can access it (frame_locator) and dispatch keys/clicks to its canvas.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Optional, Callable

from playwright.sync_api import (
    sync_playwright,
    Page,
    Frame,
    BrowserContext,
    TimeoutError as PWTimeout,
)

# ----------------------------- configuration --------------------------------

ROOT = Path(__file__).resolve().parent.parent  # /home/hy258/cadence
STATE_DIR = Path.home() / ".cache" / "cadence_runner"
STATE_DIR.mkdir(parents=True, exist_ok=True)
STATE_FILE = STATE_DIR / "storage_state.json"
CONFIG_FILE = STATE_DIR / "config.json"
DEFAULT_DL_DIR = STATE_DIR / "downloads"
DEFAULT_DL_DIR.mkdir(parents=True, exist_ok=True)

DEFAULT_CONFIG = {
    "base_url": "https://cpipc.cadencecloud.cn",
    "username": "haoyu",
    "password": "haoyu123",  # current password (post-change)
    "initial_password": "XNs6fxgm",  # only used if first-time
    "room_id": "e56bb0dc-8638-428f-82eb-64b4063e1935",
    # 1920x1080 matches what the prior successful keystroke probe used. Smaller
    # viewports cause the iframe canvas to come back at unpredictable sizes and
    # make the upper-left "click-on-terminal" heuristic miss.
    "viewport": {"width": 1920, "height": 1080},
    "headless": True,
}


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    if CONFIG_FILE.exists():
        try:
            cfg.update(json.loads(CONFIG_FILE.read_text()))
        except Exception as e:
            print(f"[warn] failed to read {CONFIG_FILE}: {e}", file=sys.stderr)
    return cfg


def save_config(cfg: dict) -> None:
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))


def log(msg: str) -> None:
    ts = time.strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


# ----------------------------- browser plumbing -----------------------------


def make_context(p, cfg: dict, headless: Optional[bool] = None) -> BrowserContext:
    """Launch chromium with persisted cookies/origin storage."""
    if headless is None:
        headless = cfg["headless"]
    browser = p.chromium.launch(headless=headless)
    storage = str(STATE_FILE) if STATE_FILE.exists() else None
    ctx = browser.new_context(
        storage_state=storage,
        viewport=cfg["viewport"],
        accept_downloads=True,
    )
    ctx._owner_browser = browser  # type: ignore[attr-defined]  # for cleanup
    return ctx


def save_state(ctx: BrowserContext) -> None:
    ctx.storage_state(path=str(STATE_FILE))
    log(f"saved storage_state -> {STATE_FILE}")


def close_context(ctx: BrowserContext) -> None:
    try:
        save_state(ctx)
    except Exception as e:
        log(f"[warn] save_state failed: {e}")
    try:
        ctx.close()
    except Exception:
        pass
    try:
        ctx._owner_browser.close()  # type: ignore[attr-defined]
    except Exception:
        pass


# ----------------------------- login flow -----------------------------------


def is_logged_in(page: Page, cfg: dict) -> bool:
    """Navigate to /rooms; wait for redirects to settle; return True if we landed on /rooms."""
    try:
        page.goto(cfg["base_url"] + "/rooms", wait_until="domcontentloaded", timeout=60000)
    except PWTimeout:
        log(f"[debug] goto /rooms timed out, current url={page.url}")
    # Allow Keycloak SSO check + any client-side redirects
    page.wait_for_timeout(4000)
    # Settle: poll until URL stops changing for 2 consecutive seconds
    deadline = time.time() + 12
    last_url = page.url
    stable_for = 0.0
    while time.time() < deadline:
        page.wait_for_timeout(800)
        cur = page.url
        if cur == last_url:
            stable_for += 0.8
            if stable_for >= 2.0:
                break
        else:
            stable_for = 0.0
            last_url = cur
    title = page.title()
    log(f"is_logged_in: url={page.url[:120]!r} title={title!r}")
    return "/rooms" in page.url and "openid-connect" not in page.url and "Sign in" not in title


def perform_login(page: Page, cfg: dict, password: Optional[str] = None) -> None:
    """Fill Keycloak login form. Handles both initial and post-change passwords."""
    pw = password or cfg["password"]
    log(f"login as {cfg['username']} ...")
    # Wait for username field (Keycloak page) — may take a moment due to redirects
    page.wait_for_selector('input[name="username"]', timeout=20000)
    page.fill('input[name="username"]', cfg["username"])
    page.fill('input[name="password"]', pw)
    # The Sign In is an <input type="submit"> with id kc-login
    page.locator('#kc-login').click()


def handle_required_actions(page: Page, cfg: dict) -> None:
    """Handle Terms&Conditions, Update password, etc. on first login."""
    for _ in range(8):  # up to ~16 sec polling
        page.wait_for_timeout(1500)
        url = page.url
        # Terms and Conditions page
        if "TERMS_AND_CONDITIONS" in url:
            log("accepting Terms & Conditions...")
            page.locator('#kc-accept').click()
            continue
        # Update password page
        if "UPDATE_PASSWORD" in url:
            log("update password page detected")
            new_pw = cfg["password"]
            page.fill('input[name="password-new"]', new_pw)
            page.fill('input[name="password-confirm"]', new_pw)
            # Submit
            page.locator('input[type="submit"]').first.click()
            continue
        # Other required actions — try Accept/Submit if any
        if "required-action" in url:
            for sel in ['#kc-accept', 'input[type="submit"]', 'button[type="submit"]']:
                if page.locator(sel).count():
                    log(f"clicking generic submit: {sel}")
                    page.locator(sel).first.click()
                    break
            continue
        # We're past it
        if "/rooms" in url and "openid-connect" not in url:
            return
    log(f"[warn] still not at /rooms after handling required actions; url={page.url}")


def login(cfg: dict, headless: Optional[bool] = None) -> None:
    """Public login entry: ensure session is alive."""
    with sync_playwright() as p:
        ctx = make_context(p, cfg, headless=headless)
        page = ctx.new_page()
        try:
            if is_logged_in(page, cfg):
                log("already logged in (cookies still valid)")
                return
            log("not logged in; starting auth flow")
            try:
                page.goto(cfg["base_url"], wait_until="commit", timeout=60000)
            except PWTimeout:
                pass
            page.wait_for_timeout(3000)
            # Two passwords to try: current, then initial (in case state was reset)
            try:
                perform_login(page, cfg, cfg["password"])
                page.wait_for_timeout(2500)
                err_loc = page.locator('.alert-error, .kc-feedback-text, #input-error')
                err_text = (err_loc.first.text_content() or "") if err_loc.count() else ""
                if "Invalid" in err_text or "invalid" in err_text:
                    raise RuntimeError(f"invalid pw with stored password: {err_text!r}")
            except Exception as e:
                log(f"current password did not work ({e}); retrying with initial password")
                try:
                    page.goto(cfg["base_url"], wait_until="commit", timeout=60000)
                except PWTimeout:
                    pass
                page.wait_for_timeout(3000)
                perform_login(page, cfg, cfg["initial_password"])
            handle_required_actions(page, cfg)
            if "/rooms" in page.url:
                log("login OK — at /rooms")
            else:
                log(f"[warn] post-login url is {page.url}")
        finally:
            close_context(ctx)


# ----------------------------- room navigation ------------------------------


def _dismiss_fullscreen_iframe(page: Page) -> None:
    """If the App Presenter iframe is in fullscreen modal mode, click Exit maximize."""
    try:
        em = page.get_by_role("button", name=re.compile("Exit maximize", re.I))
        if em.count():
            log("Exit maximize found — collapsing iframe modal")
            em.first.click(force=True)
            page.wait_for_timeout(800)
    except Exception as e:
        log(f"[debug] _dismiss_fullscreen_iframe: {e}")


def goto_room(page: Page, cfg: dict, *, dismiss_iframe: bool = True) -> None:
    """Navigate into the room.

    `dismiss_iframe=True` clicks the iframe's Exit-maximize button so that the
    surrounding page chrome (FILES tab, Join button, etc.) becomes clickable.
    Set `dismiss_iframe=False` when the caller needs the noVNC iframe to remain
    in fullscreen mode for keyboard/mouse input — e.g. when driving the desktop.
    """
    target = f"{cfg['base_url']}/rooms/{cfg['room_id']}"
    if not page.url.startswith(target):
        try:
            page.goto(target, wait_until="domcontentloaded", timeout=60000)
        except PWTimeout:
            log(f"[debug] goto_room timed out on domcontentloaded; url={page.url}")
        page.wait_for_timeout(3000)
    if dismiss_iframe:
        # Collapse modal iframe if it's covering the chrome
        _dismiss_fullscreen_iframe(page)
        # Wait for page chrome
        try:
            page.wait_for_selector('text=Start Mate Desktop', timeout=20000)
        except PWTimeout:
            log(f"[debug] 'Start Mate Desktop' not visible; current url={page.url}, title={page.title()!r}")
            log(f"[debug] body snippet: {page.locator('body').inner_text()[:500]!r}")
            raise


def goto_files(page: Page, cfg: dict) -> None:
    goto_room(page, cfg)
    _dismiss_fullscreen_iframe(page)
    # Prefer the data-test-id; fall back to role/name
    files_tab = page.locator('[data-test-id="files-tab"]')
    if files_tab.count() == 0:
        files_tab = page.get_by_role("tab", name=re.compile(r"^files$", re.I))
    log(f"files_tab count={files_tab.count()}")
    files_tab.first.click(force=True)
    page.wait_for_timeout(1500)
    # Wait for either an "Upload" button OR an existing file row OR the empty placeholder
    deadline = time.time() + 20
    while time.time() < deadline:
        body = page.locator('body').inner_text()
        if "Upload" in body or "shared here" in body or "Drop files" in body or "Supported file types" in body:
            return
        page.wait_for_timeout(500)
    # diagnostic
    shot = STATE_DIR / "goto_files_failed.png"
    page.screenshot(path=str(shot))
    body = page.locator('body').inner_text()
    log(f"[debug] goto_files: tab clicked but Files UI not visible. body[:600]={body[:600]!r}")
    log(f"[debug] screenshot -> {shot}")
    raise RuntimeError("Files tab UI did not load")


# ----------------------------- file operations ------------------------------


def _scrape_files_rows(page: Page) -> list[dict]:
    """Read the FILES table. Returns list of {name, type, size, uploaded_at, uploader}."""
    out: list[dict] = []
    # Each file row contains a roomCardMoreBtn; the row is its closest tr/MuiTableRow ancestor
    more_btns = page.locator('[data-test-id="roomCardMoreBtn"]')
    n = more_btns.count()
    for i in range(n):
        # Find the row text via the nearest ancestor
        try:
            row_text = more_btns.nth(i).evaluate("""(el) => {
                let p = el;
                while (p && p.tagName !== 'TR' && !(p.getAttribute && p.getAttribute('role') === 'row')) {
                    p = p.parentElement;
                    if (!p) break;
                }
                return (p || el.parentElement).innerText;
            }""")
        except Exception:
            row_text = ""
        # Parse: "name\nTYPE\nSIZE\nDATE\nUPLOADER"
        parts = [s.strip() for s in (row_text or "").split("\n") if s.strip()]
        rec = {"raw": " | ".join(parts)}
        if parts:
            rec["name"] = parts[0]
        if len(parts) >= 3:
            rec["type"] = parts[1]
            rec["size"] = parts[2]
        if len(parts) >= 4:
            rec["uploaded_at"] = parts[3]
        out.append(rec)
    return out


def list_files(cfg: dict) -> list[dict]:
    """Return list of files currently on the FILES tab."""
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            goto_files(page, cfg)
            page.wait_for_timeout(2000)
            return _scrape_files_rows(page)
        finally:
            close_context(ctx)


def upload(cfg: dict, file_path: str) -> bool:
    """Upload a single file via the FILES tab. Bypasses OS file picker."""
    file_path = str(Path(file_path).resolve())
    if not os.path.exists(file_path):
        raise FileNotFoundError(file_path)
    log(f"upload {file_path}")
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            goto_files(page, cfg)
            # Find the hidden <input type="file">. Try direct selector first.
            file_input = page.locator('input[type="file"]').first
            if file_input.count() == 0:
                # Sometimes the input is appended only after the button is clicked.
                page.expect_file_chooser(timeout=2000)  # may not fire
                file_input = page.locator('input[type="file"]').first
            log(f"input[type=file] count={page.locator('input[type=file]').count()}")
            file_input.set_input_files(file_path)
            log("set_input_files done; waiting for upload to register...")
            # Wait for either a success row or a progress indicator
            for _ in range(30):
                page.wait_for_timeout(1000)
                body = page.locator('body').inner_text()
                if Path(file_path).name in body:
                    log("file appears on the page — upload OK")
                    return True
            log("[warn] file name did not appear within 30s; check via list")
            return False
        finally:
            close_context(ctx)


def download(cfg: dict, name: str, out_dir: Optional[str] = None) -> Optional[str]:
    """Download a file by its visible name from the FILES tab."""
    out_dir = out_dir or str(DEFAULT_DL_DIR)
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            goto_files(page, cfg)
            page.wait_for_timeout(2000)
            # Locate the row that contains the name, then click the row's 3-dot menu
            # Strategy: find the first roomCardMoreBtn whose ancestor row contains `name`
            more_btns = page.locator('[data-test-id="roomCardMoreBtn"]')
            n = more_btns.count()
            target_idx = -1
            for i in range(n):
                row_text = more_btns.nth(i).evaluate(
                    "(el) => { let p=el; while(p && p.tagName!=='TR' && !(p.getAttribute && p.getAttribute('role')==='row')) p=p.parentElement; return (p||el.parentElement).innerText; }"
                )
                if name in (row_text or ""):
                    target_idx = i
                    break
            if target_idx < 0:
                raise RuntimeError(f"file {name!r} not found in FILES list (have {n} files)")
            log(f"opening menu for row #{target_idx} ({name})")
            more_btns.nth(target_idx).click()
            page.wait_for_selector('[data-test-id="download-file-menu-item"]', timeout=10000)
            target = Path(out_dir) / name
            with page.expect_download(timeout=120000) as dl_info:
                page.locator('[data-test-id="download-file-menu-item"]').click()
            dl = dl_info.value
            # Use the original name if suggested_filename is empty/odd
            suggested = dl.suggested_filename or name
            target = Path(out_dir) / suggested
            dl.save_as(str(target))
            log(f"downloaded -> {target}")
            return str(target)
        finally:
            close_context(ctx)


def delete_remote_file(cfg: dict, name: str) -> bool:
    """Delete a file from the remote FILES tab."""
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            goto_files(page, cfg)
            page.wait_for_timeout(2000)
            more_btns = page.locator('[data-test-id="roomCardMoreBtn"]')
            n = more_btns.count()
            for i in range(n):
                row_text = more_btns.nth(i).evaluate(
                    "(el) => { let p=el; while(p && p.tagName!=='TR' && !(p.getAttribute && p.getAttribute('role')==='row')) p=p.parentElement; return (p||el.parentElement).innerText; }"
                )
                if name in (row_text or ""):
                    more_btns.nth(i).click()
                    page.wait_for_selector('[data-test-id="delete-file-menu-item"]', timeout=10000)
                    page.locator('[data-test-id="delete-file-menu-item"]').click()
                    page.wait_for_timeout(800)
                    # confirmation dialog: click whichever Confirm/Yes/Delete button appears
                    for btn_name in ["Delete", "Confirm", "Yes", "OK"]:
                        b = page.get_by_role("button", name=re.compile(f"^{btn_name}$", re.I))
                        if b.count():
                            b.first.click()
                            page.wait_for_timeout(1000)
                            log(f"deleted {name}")
                            return True
                    log("[warn] delete clicked but no confirm dialog found")
                    return True
            log(f"{name!r} not found")
            return False
        finally:
            close_context(ctx)


# ----------------------------- desktop driver -------------------------------


class Desktop:
    """Drive the Mate Desktop noVNC canvas inside the App Presenter iframe."""

    def __init__(self, page: Page, frame: Frame, shots_dir: Optional[Path] = None):
        self.page = page
        self.frame = frame
        self.canvas = frame.locator("canvas").first
        self.shots_dir = shots_dir or (STATE_DIR / "shots")
        self.shots_dir.mkdir(parents=True, exist_ok=True)
        self._shot_idx = 0
        # Read canvas geometry (CSS pixels for clicks; drawing-buffer pixels for rendering)
        info = frame.evaluate(
            """() => { const c=document.querySelector('canvas'); if(!c) return null;
                       const r=c.getBoundingClientRect();
                       return {x:r.x, y:r.y, w:r.width, h:r.height, dw:c.width, dh:c.height}; }"""
        )
        if not info:
            raise RuntimeError("noVNC canvas not found in iframe")
        self.box = info  # {x, y, w, h, dw, dh}

    @classmethod
    def attach(cls, page: Page, cfg: dict, *, do_join: bool = True,
               wait_canvas_s: float = 60.0, wait_paint_s: float = 60.0) -> "Desktop":
        """Navigate to the room, optionally Join, then return a Desktop wrapper.

        Also waits until the canvas actually contains non-trivial pixels (i.e. the
        Mate Desktop has finished painting) before returning.

        IMPORTANT: We do NOT exit-maximize the iframe here. Exit-maximize collapses
        the canvas and (more importantly) moves browser focus back to the parent
        page, so subsequent page.keyboard.type calls go nowhere. The iframe stays
        in its default fullscreen-modal state while we drive the desktop.
        """
        goto_room(page, cfg, dismiss_iframe=False)
        if do_join:
            # If a remote session needs starting first
            sr = page.get_by_role("button", name=re.compile("Start remote", re.I))
            if sr.count():
                log("starting remote session...")
                sr.first.click(force=True)
                # Wait for Join to appear (session boot can take 30-60s)
                try:
                    page.wait_for_selector('text=Join', timeout=120000)
                except PWTimeout:
                    log("[warn] Join button never appeared after Start remote")
            join = page.get_by_role("button", name=re.compile("^Join$", re.I))
            if join.count():
                join.first.click(force=True)
                page.wait_for_timeout(2500)
        # Wait for noVNC frame
        deadline = time.time() + wait_canvas_s
        frame = None
        while time.time() < deadline:
            for fr in page.frames:
                if "/beta-vnc/" in fr.url:
                    try:
                        if fr.locator("canvas").count() > 0:
                            frame = fr
                            break
                    except Exception:
                        pass
            if frame:
                break
            page.wait_for_timeout(500)
        if not frame:
            raise RuntimeError("noVNC iframe never appeared")
        # Wait for canvas to actually paint (non-blank)
        log("waiting for desktop to finish painting...")
        deadline = time.time() + wait_paint_s
        last_hash: Optional[str] = None
        stable_for = 0
        while time.time() < deadline:
            page.wait_for_timeout(1500)
            sample = frame.evaluate(
                """() => { const c=document.querySelector('canvas'); if(!c) return null;
                           try {
                             const ctx=c.getContext('2d');
                             // sample pixel grid 5x5
                             const w=c.width, h=c.height;
                             let s='';
                             for (let i=1;i<=5;i++) for (let j=1;j<=5;j++) {
                               const d=ctx.getImageData((w*i/6)|0,(h*j/6)|0,1,1).data;
                               s += d[0]+','+d[1]+','+d[2]+';';
                             }
                             return s;
                           } catch(e) { return 'err:'+e.message; }
                         }"""
            )
            if not sample or sample.startswith("err"):
                continue
            # Blank/white screens have very low pixel diversity
            uniq = len(set(sample.split(';')))
            if uniq >= 6:
                if sample == last_hash:
                    stable_for += 1
                    if stable_for >= 2:  # ~3s stable
                        break
                else:
                    stable_for = 0
                    last_hash = sample
        log(f"desktop painted (stable={stable_for}, deadline_left={int(deadline-time.time())}s)")
        return cls(page, frame)

    # --- screenshots ---
    def screenshot(self, label: str = "shot") -> Path:
        data = self.frame.evaluate(
            "() => { const c=document.querySelector('canvas'); return c?c.toDataURL('image/png'):null; }"
        )
        if not data:
            raise RuntimeError("canvas screenshot failed")
        self._shot_idx += 1
        out = self.shots_dir / f"{int(time.time())}_{self._shot_idx:03d}_{label}.png"
        out.write_bytes(base64.b64decode(data.split(",", 1)[1]))
        return out

    # --- mouse ---
    def click(self, x: float, y: float, button: str = "left") -> None:
        self.canvas.click(position={"x": x, "y": y}, button=button, force=True)

    def right_click(self, x: float, y: float) -> None:
        self.click(x, y, button="right")

    # --- keyboard ---
    # noVNC listens for key events at the document level inside the iframe.
    # Once a click on the canvas has put focus on the iframe document, the outer
    # page's keyboard events propagate down and noVNC forwards them via WebSocket
    # to the VNC server. So `self.page.keyboard.type/press` is correct — but
    # callers MUST avoid clicking outside the focused window between focusing
    # and typing, or focus is lost.
    def press(self, key: str, count: int = 1, gap_ms: int = 120) -> None:
        for _ in range(count):
            self.page.keyboard.press(key)
            if count > 1:
                self.page.wait_for_timeout(gap_ms)

    def type(self, text: str, delay_ms: int = 60) -> None:
        # noVNC over WebSocket occasionally drops keyup events when characters
        # arrive too fast, which the VNC server then interprets as a held key
        # and auto-repeats (we saw "IIIIIIIII..." or "ggggggg..." injected into
        # base64 strings). Mitigation: emit explicit down/up per character with
        # a hold gap, and pause every few chars so the event queue drains.
        kb = self.page.keyboard
        for idx, ch in enumerate(text):
            kb.down(ch)
            self.page.wait_for_timeout(15)
            kb.up(ch)
            self.page.wait_for_timeout(delay_ms)
            if idx and idx % 16 == 0:
                self.page.wait_for_timeout(120)

    # --- high-level: open terminal via desktop right-click menu ---
    def open_terminal(self) -> None:
        """Right-click on empty desktop area, then arrow-key to 'Open in Terminal'."""
        # Pick a corner unlikely to have a window: bottom-right of desktop
        cx, cy = self.box["w"] * 0.85, self.box["h"] * 0.6
        self.right_click(cx, cy)
        self.page.wait_for_timeout(900)
        # Mate desktop right-click menu order:
        #   Create Folder, Create Launcher, Create Document, Open in Terminal, ...
        # Down-arrow 4 times then Enter.
        self.press("ArrowDown", count=4, gap_ms=130)
        self.press("Enter")
        self.page.wait_for_timeout(2500)

    def click_terminal(self) -> None:
        """Click somewhere on a likely-open terminal window to focus it."""
        # Heuristic: most often terminal opens near upper-left of desktop
        self.click(self.box["w"] * 0.25, self.box["h"] * 0.20)
        self.page.wait_for_timeout(400)

    def run_cmd(self, cmd: str, after_ms: int = 800) -> None:
        """Type a command + Enter. Caller is responsible for ensuring focus is on terminal."""
        self.type(cmd)
        self.page.wait_for_timeout(150)
        self.press("Enter")
        self.page.wait_for_timeout(after_ms)

    # alias requested by spec
    def type_cmd(self, cmd: str, after_ms: int = 800) -> None:
        return self.run_cmd(cmd, after_ms=after_ms)


# --- terminal-output polling via FILES drop ---------------------------------


def poll_until_marker(cfg: dict, marker_name: str, *,
                       timeout_s: float = 600.0, interval_s: float = 15.0) -> Optional[dict]:
    """Poll the FILES tab every `interval_s` seconds until a row whose name contains
    `marker_name` appears. Returns the matching row dict, or None on timeout.

    Used as a synchronization primitive: the remote terminal writes a sentinel file
    into the shared FILES dir when a job finishes, and we wait for it to appear here.
    """
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            items = list_files(cfg)
        except Exception as e:
            log(f"[warn] list_files failed in poll: {e}")
            items = []
        for it in items:
            if marker_name in (it.get("name") or "") or marker_name in (it.get("raw") or ""):
                log(f"poll_until_marker: {marker_name!r} appeared")
                return it
        time.sleep(interval_s)
    log(f"poll_until_marker: timed out waiting for {marker_name!r}")
    return None


# ----------------------------- recon helper ---------------------------------


RECON_SCRIPT = r"""
set +e
OUT=/tmp/cadence_recon.log
{
  echo "=== whoami / host / kernel ==="
  whoami; id; hostname; uname -a; date
  echo "=== home tree (top) ==="
  ls -la ~ 2>&1 | head -80
  echo "=== candidate shared dirs ==="
  for d in ~/shared ~/Shared ~/Public ~/Documents ~/Desktop /shared /home/shared /vfs /mnt/shared /home/*/shared /home/*/Shared; do
    for d2 in $d; do
      [ -d "$d2" ] && { echo "--- $d2 ---"; ls -la "$d2" 2>&1 | head -30; }
    done
  done
  echo "=== mountpoints ==="
  mount 2>&1 | grep -vE '^(proc|sysfs|tmpfs|devpts|cgroup|securityfs|debugfs|mqueue|fusectl)' | head -40
  df -h 2>&1 | head -30
  echo "=== find uploaded submission.tar.gz ==="
  find / -maxdepth 6 -name 'submission.tar.gz' \
       -not -path '/proc/*' -not -path '/sys/*' -not -path '/snap/*' \
       2>/dev/null | head -20
  echo "=== try cds.lib / hdl.var anywhere ==="
  find / -maxdepth 6 \( -name cds.lib -o -name hdl.var \) -not -path '/proc/*' -not -path '/sys/*' 2>/dev/null | head -20
  echo "=== modules ==="
  ( type module 2>/dev/null && module avail 2>&1 | head -120 ) || echo "(no modules subsystem)"
  echo "=== which Cadence tools ==="
  for t in xrun xmsim xmverilog xmcompile xmelab xmvlog ncsim ncverilog ncvlog ncelab \
           genus joules innovus virtuoso vmanager modus tempus voltus pegasus; do
    p=$(command -v $t 2>/dev/null); [ -n "$p" ] && echo "$t -> $p"
  done
  echo "=== look for installed Cadence trees ==="
  for base in /tools /opt /apps /eda /usr/local /home; do
    [ -d "$base" ] || continue
    find "$base" -maxdepth 4 -type d \( \
        -iname 'XCELIUM*' -o -iname 'GENUS*' -o -iname 'INNOVUS*' -o \
        -iname 'CONFRML*' -o -iname 'INCISIV*' -o -iname 'cadence*' -o \
        -iname 'IUS*' -o -iname 'MMSIM*' \
      \) 2>/dev/null | head -40
  done
  echo "=== /tools /opt /apps top ==="
  for d in /tools /opt /apps /eda; do
    [ -d "$d" ] && { echo "--- $d ---"; ls -la "$d" 2>&1 | head -40; }
  done
  echo "=== Cadence env hints ==="
  env | grep -iE 'cadence|cds|xcelium|genus|mmsim|incisiv|XLM|innovus' | head -40
  echo "=== /etc/profile.d ==="
  ls /etc/profile.d/ 2>&1 | head -40
  for f in /etc/profile.d/*cadence* /etc/profile.d/*cds* /etc/profile.d/*xcelium* /etc/profile.d/*genus*; do
    [ -f "$f" ] && { echo "--- $f ---"; sed -n '1,80p' "$f"; }
  done
  echo "=== existing .cadence / .cdsrc / .bashrc tail ==="
  ls -la ~/.cadence ~/.cds.lib ~/.cdsenv ~/cds.lib 2>&1 | head -20
  for rc in ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc; do
    [ -f "$rc" ] && { echo "--- $rc (tail) ---"; tail -50 "$rc"; }
  done
  echo "=== licensing hints ==="
  env | grep -iE 'LM_LICENSE|CDS_LIC|LICENSE' | head -20
  echo "=== DONE ==="
} > "$OUT" 2>&1
echo "RECON_DONE_MARKER"
"""


# Candidate share dirs the FILES tab MIGHT map to, in priority order
SHARE_CANDIDATES = [
    "~/shared", "~/Shared", "~/share",
    "~/Public", "~/Documents", "~/Desktop",
    "/shared", "/home/shared", "/data/shared",
    "/vfs", "/mnt/shared", "/srv/shared",
    "/home/user/shared", "/home/cadence/shared",
]


RECON_SCRIPT = r"""#!/usr/bin/env bash
set +e
OUT=__OUT__
{
  echo === whoami ===
  whoami; id; hostname; date
  echo === FIND submission.tar.gz ===
  # the location of the uploaded tarball IS the FILES-tab share dir
  find / -maxdepth 8 -name 'submission.tar.gz' \
       -not -path '/proc/*' -not -path '/sys/*' -not -path '/snap/*' \
       2>/dev/null
  echo === which ===
  for t in xrun xmsim xmverilog xmvlog xmelab ncsim ncverilog genus joules innovus virtuoso vmanager; do
    p=$(command -v $t 2>/dev/null); [ -n "$p" ] && echo "$t -> $p"
  done
  echo === env CDS ===
  env | grep -iE 'cadence|cds|xcelium|genus' | head -40
  echo === module avail ===
  (type module >/dev/null 2>&1 && module avail 2>&1 | head -120) || echo no-modules
  echo === ls home ===
  ls -la $HOME 2>&1 | head -40
  echo === share candidates ===
  for s in __SHARES__; do d=$(eval echo $s); [ -d "$d" ] && echo "DIR $d" && ls -la "$d" 2>&1 | head -20; done
  echo === mounts ===
  mount 2>&1 | grep -vE '^(proc|sysfs|tmpfs|devpts|cgroup|securityfs|debugfs|mqueue|fusectl)' | head -30
  echo === DONE ===
} > "$OUT" 2>&1
# Copy the log into every candidate share dir (any one that's the actual FILES
# share will surface in the FILES tab; we identify it after the fact).
for s in __SHARES__; do d=$(eval echo $s); [ -d "$d" ] && cp "$OUT" "$d/__LOG_NAME__"; done
# Also try the directory that contains submission.tar.gz (definitely FILES)
SUBM_DIR=$(dirname "$(find / -maxdepth 8 -name 'submission.tar.gz' -not -path '/proc/*' -not -path '/sys/*' 2>/dev/null | head -1)")
[ -n "$SUBM_DIR" ] && [ -d "$SUBM_DIR" ] && cp "$OUT" "$SUBM_DIR/__LOG_NAME__" && echo "ALSO_COPIED_TO=$SUBM_DIR"
echo COPIED_TO_SHARES_DONE
"""


def remote_peek(cfg: dict) -> None:
    """Attach to the desktop and screenshot the current terminal — no input."""
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            d = Desktop.attach(page, cfg)
            shot = d.screenshot("peek")
            log(f"peek -> {shot}")
        finally:
            close_context(ctx)


def remote_exec(cfg: dict, cmd: str, after_ms: int = 4000) -> None:
    """Attach, focus the terminal, run a bash one-liner via base64. Caller's
    shell on the remote VM is tcsh, so we always wrap with `bash -c` and ship
    the actual command as base64 to dodge quoting/escape headaches.
    """
    b64 = base64.b64encode(cmd.encode()).decode()
    # tcsh-safe: no $() / no 2>&1 in the wrapper itself. Pipe base64 -> bash.
    wrapper = f"echo {b64} | base64 -d | bash"
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            d = Desktop.attach(page, cfg)
            d.click(350, 200)
            d.page.wait_for_timeout(600)
            d.page.keyboard.press("Control+c")
            d.page.wait_for_timeout(200)
            d.run_cmd(wrapper, after_ms=after_ms)
            shot = d.screenshot("exec")
            log(f"exec -> {shot}")
        finally:
            close_context(ctx)


def remote_check(cfg: dict) -> None:
    """Open the Mate Desktop terminal, query a small set of well-known things
    (which xrun, which genus, env vars, candidate share dirs), then drop the
    log file onto every candidate share dir so we can pick it up via FILES.

    The script is base64-encoded and decoded on the remote — that way no
    special character (quotes, $, |, multi-line) ever has to survive the VNC
    keyboard mapping; we only ever type ASCII letters, digits, +, /, =.
    """
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            d = Desktop.attach(page, cfg)
            d.screenshot("check_00_attached")
            # Focus the existing terminal window. The previous probe established
            # (350, 200) in CSS pixels lands cleanly inside the terminal window.
            d.click(350, 200)
            d.page.wait_for_timeout(800)
            # In case a previous heredoc / process is hanging, send Ctrl-C twice.
            d.page.keyboard.press("Control+c")
            d.page.wait_for_timeout(200)
            d.page.keyboard.press("Control+c")
            d.page.wait_for_timeout(400)
            d.screenshot("check_01_focused")
            # Quick liveness ping
            d.run_cmd("pwd; date", after_ms=1500)
            d.screenshot("check_02_after_ping")
            # Build the recon script
            tag = time.strftime("%Y%m%d_%H%M%S")
            log_name = f"cadence_env_{tag}.log"
            script_path = f"/tmp/cadence_env_{tag}.sh"
            shares_list = " ".join(f'"{s}"' for s in SHARE_CANDIDATES)
            script_text = (
                RECON_SCRIPT
                .replace("__OUT__", f"/tmp/{log_name}")
                .replace("__LOG_NAME__", log_name)
                .replace("__SHARES__", shares_list)
            )
            # base64 the script so we never type special characters at the VNC layer
            script_b64 = base64.b64encode(script_text.encode()).decode()
            # echo the b64 (one long line, ASCII-only) into the file, decode, run
            d.run_cmd(
                f"echo {script_b64} | base64 -d > {script_path} && bash {script_path}",
                after_ms=5000,
            )
            d.screenshot("check_03_after_recon")
            log(f"remote_check finished — poll FILES for {log_name}")
        finally:
            close_context(ctx)


# ----------------------------- desktop probe --------------------------------


def probe_desktop(cfg: dict) -> None:
    """See what we can do with the App Presenter iframe."""
    with sync_playwright() as p:
        ctx = make_context(p, cfg)
        page = ctx.new_page()
        try:
            goto_room(page, cfg)
            page.wait_for_timeout(2000)
            # Make sure APPLICATIONS tab is selected
            apps_tab = page.get_by_role("tab", name=re.compile("Application", re.I))
            if apps_tab.count():
                apps_tab.click()
                page.wait_for_timeout(1000)
            # If no session yet, click Start remote
            if page.get_by_role("button", name=re.compile("Start remote", re.I)).count():
                log("starting remote session...")
                page.get_by_role("button", name=re.compile("Start remote", re.I)).click()
                # Wait for Join button to appear
                page.wait_for_selector('text=Join', timeout=60000)
            # Click Join
            join_btn = page.get_by_role("button", name=re.compile("^Join$", re.I))
            if join_btn.count():
                log("clicking Join...")
                # Exit maximize first if iframe is covering
                exit_max = page.get_by_role("button", name=re.compile("Exit maximize", re.I))
                if exit_max.count():
                    exit_max.click()
                    page.wait_for_timeout(800)
                join_btn.click()
                page.wait_for_timeout(3000)
            # Inspect frames
            log(f"top-level frames in page: {len(page.frames)}")
            for i, f in enumerate(page.frames):
                log(f"  frame[{i}] name={f.name!r} url={f.url[:80]!r}")
            # Try to access the App Presenter iframe
            try:
                fl = page.frame_locator('iframe[title="App Presenter"]')
                count = fl.locator('canvas').count()
                log(f"frame_locator(App Presenter) → canvas count = {count}")
                if count > 0:
                    log("=> we CAN reach noVNC canvas via Playwright! method A is feasible")
            except Exception as e:
                log(f"frame_locator failed: {e}")
            # Save a screenshot for manual inspection
            shot = STATE_DIR / "probe_screenshot.png"
            page.screenshot(path=str(shot), full_page=True)
            log(f"screenshot -> {shot}")
        finally:
            close_context(ctx)


# ----------------------------- CLI ------------------------------------------


def main() -> int:
    cfg = load_config()
    save_config(cfg)  # ensure file exists for user inspection

    ap = argparse.ArgumentParser(prog="cadence_runner")
    ap.add_argument("--no-headless", action="store_true", help="show browser window (needs DISPLAY)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("login")
    sub.add_parser("status")
    sub.add_parser("list")
    p_up = sub.add_parser("upload")
    p_up.add_argument("path")
    p_dl = sub.add_parser("download")
    p_dl.add_argument("name")
    p_dl.add_argument("out", nargs="?", default=None)
    p_rm = sub.add_parser("rm")
    p_rm.add_argument("name")
    sub.add_parser("probe")
    sub.add_parser("check")
    sub.add_parser("peek")
    p_exec = sub.add_parser("exec")
    p_exec.add_argument("oneliner", help="single-line shell command to type into terminal")
    p_exec.add_argument("--after", type=int, default=4000)
    p_poll = sub.add_parser("poll")
    p_poll.add_argument("marker")
    p_poll.add_argument("--timeout", type=float, default=900.0)
    p_poll.add_argument("--interval", type=float, default=20.0)
    p_run = sub.add_parser("run")
    p_run.add_argument("--share", default=None,
                       help="absolute path on remote VM that maps to FILES tab")
    p_run.add_argument("--tar", default="submission.tar.gz",
                       help="name of the (already uploaded) submission tarball")
    p_run.add_argument("--no-synth", action="store_true",
                       help="run baseline simulation only, skip synthesis")
    p_run.add_argument("--results-name", default=None,
                       help="override result tarball name (default: results_<ts>.tar.gz)")

    args = ap.parse_args()
    if args.no_headless:
        cfg["headless"] = False

    if args.cmd == "login":
        login(cfg)
    elif args.cmd == "status":
        login(cfg)
        log("status: session refreshed")
    elif args.cmd == "list":
        items = list_files(cfg)
        for it in items:
            print(json.dumps(it, ensure_ascii=False))
    elif args.cmd == "upload":
        ok = upload(cfg, args.path)
        return 0 if ok else 1
    elif args.cmd == "download":
        path = download(cfg, args.name, args.out)
        return 0 if path else 1
    elif args.cmd == "rm":
        ok = delete_remote_file(cfg, args.name)
        return 0 if ok else 1
    elif args.cmd == "probe":
        probe_desktop(cfg)
    elif args.cmd == "check":
        remote_check(cfg)
    elif args.cmd == "peek":
        remote_peek(cfg)
    elif args.cmd == "exec":
        remote_exec(cfg, args.oneliner, after_ms=args.after)
    elif args.cmd == "poll":
        hit = poll_until_marker(cfg, args.marker, timeout_s=args.timeout, interval_s=args.interval)
        return 0 if hit else 1
    elif args.cmd == "run":
        ok = run_flow(cfg, share_dir=args.share, tar_name=args.tar,
                      do_synth=not args.no_synth, results_name=args.results_name)
        return 0 if ok else 1
    else:
        ap.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
