from pathlib import Path

path = Path("src/kleinanzeigen_api/cli.py")
source = path.read_text()

source = source.replace("import json\n", "import json\nimport re\n", 1)
snippet = '''\ndef _ad_id(value: str) -> str:
    """Accept a numeric ad id or a canonical Kleinanzeigen listing URL."""
    if value.isdigit():
        return value
    match = re.search(r"/(\\d+)-\\d+-\\d+/?(?:[?#].*)?$", value)
    if match:
        return match.group(1)
    raise ValueError("ad must be a numeric id or a Kleinanzeigen listing URL")


def _conversation_id(payload: object) -> str | None:
    """Extract the new conversation id from known gateway response shapes."""
    if not isinstance(payload, dict):
        return None
    for key in ("conversationId", "conversation_id", "id"):
        value = payload.get(key)
        if isinstance(value, (str, int)) and str(value):
            return str(value)
    for key in ("conversation", "data"):
        value = _conversation_id(payload.get(key))
        if value:
            return value
    return None


def _cmd_send(argv) -> int:
    ap = argparse.ArgumentParser(
        prog="kleinanzeigen-api send",
        description="Start a chat on an ad and send its first message.")
    ap.add_argument("ad", help="numeric ad id or canonical Kleinanzeigen listing URL")
    ap.add_argument("--contact-name", required=True,
                    help="your name shown to the seller")
    ap.add_argument("--message", required=True, help="message text to send")
    ap.add_argument("--confirm", action="store_true",
                    help="required to create the conversation and send the message")
    a = ap.parse_args(argv)
    ad_id = _ad_id(a.ad)

    if not a.confirm:
        print(f"Draft for ad {ad_id} as {a.contact_name}:\\n\\n{a.message}\\n")
        print("Not sent. Re-run with --confirm to create the chat and send it.",
              file=sys.stderr)
        return 0

    api = _authed_client()
    conversation = api.start_conversation(ad_id, a.contact_name)
    conversation_id = _conversation_id(conversation)
    if not conversation_id:
        raise RuntimeError(
            "Could not find a conversation id in the create-conversation response")
    api.reply(conversation_id, a.message)
    print(f"sent in conversation {conversation_id}", file=sys.stderr)
    return 0


'''

marker = "def _cmd_my_ads(argv) -> int:\n"
if source.count(marker) != 1:
    raise RuntimeError("could not find the CLI insertion point")
source = source.replace(marker, snippet + marker, 1)

subcommand = '"messages": _cmd_messages, "my-ads": _cmd_my_ads,'
if source.count(subcommand) != 1:
    raise RuntimeError("could not find the CLI subcommand table")
source = source.replace(
    subcommand,
    '"messages": _cmd_messages, "send": _cmd_send, "my-ads": _cmd_my_ads,',
    1,
)

path.write_text(source)
