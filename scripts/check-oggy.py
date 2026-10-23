"""Check oggy from the external gateway and report outages to Telegram."""

import json
import os
from pathlib import Path
import tempfile
import time
from urllib import error, parse, request


HEALTH_URL = "https://headscale.killeik.net/health"
STATE_PATH = Path("/var/lib/oggy-watch/state.json")
REPEAT_SECONDS = 4 * 60 * 60


def healthy():
    try:
        # Never let a proxy or redirect turn another endpoint into a healthy oggy.
        class NoRedirect(request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None

        opener = request.build_opener(request.ProxyHandler({}), NoRedirect())
        with opener.open(HEALTH_URL, timeout=10) as response:
            return response.status == 200
    except error.HTTPError as response:
        response.close()
        return False
    except Exception:
        return False


def notify(message):
    try:
        token = os.environ["QINGPING_TELEGRAM_TOKEN"]
        chat_id = os.environ["QINGPING_TELEGRAM_CHAT_ID"]
        data = parse.urlencode({"chat_id": chat_id, "text": message}).encode()
        req = request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage", data=data
        )
        with request.urlopen(req, timeout=10) as response:
            return json.loads(response.read(65536)).get("ok") is True
    except error.HTTPError as response:
        response.close()
        return False
    except Exception:
        # urllib exceptions can contain the bot token and response contents.
        return False


def save_state(state):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", dir=STATE_PATH.parent, prefix=".state-", delete=False
        ) as output:
            temporary = Path(output.name)
            json.dump(state, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, STATE_PATH)
        directory = os.open(STATE_PATH.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    os.umask(0o077)
    try:
        state = json.loads(STATE_PATH.read_text())
    except FileNotFoundError:
        state = {"failures": 0, "last_sent": None}

    now = time.time()
    message = None
    if healthy():
        state["failures"] = 0
        if state["last_sent"] is not None:
            message = "Все, молчу. Headscale снова доступен снаружи."
    else:
        state["failures"] = min(state["failures"] + 1, 3)
        if state["failures"] >= 3 and (
            state["last_sent"] is None
            or now - state["last_sent"] >= REPEAT_SECONDS
        ):
            message = (
                "Headscale не отвечает снаружи. "
                "Три проверки подряд не прошли. "
                "Проверь oggy, VPS-шлюз и домашний интернет."
            )

    if message is not None:
        if notify(message):
            state["last_sent"] = now if state["failures"] else None
            print("Telegram notification delivered.")
        else:
            print("Telegram notification failed; will retry on the next check.")
    save_state(state)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Keep credentials and unexpected state/HTTP contents out of the journal.
        print("oggy-watch failed to process or persist its state.", flush=True)
        raise SystemExit(1)
