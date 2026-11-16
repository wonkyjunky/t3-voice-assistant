#!/usr/bin/env python3
"""Stop the assistant from creating work threads that are themselves the assistant.

Runs as a Claude Code PreToolUse hook for the assistant instance only. A thread started
without an explicit model inherits the secretary's own setup, so the new thread would talk,
and be read aloud, like the secretary. This hook blocks such calls and tells the model the
exact values to use, so it retries correctly. Blocking is code, not a request in a prompt.

Exit status 2 blocks the tool call and feeds stderr back to the model.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assistant_config  # noqa: E402  (this install's settings in assistant.conf)

SECRETARY_MARKER = "voice_assistant"
SECRETARY_INSTANCE = assistant_config.get("ASSISTANT_INSTANCE")
WORK_INSTANCE = assistant_config.get("WORK_INSTANCE", "claudeAgent")
WORK_MODEL = assistant_config.get("WORK_MODEL", "claude-sonnet-5-5")
BLOCK_EXIT_STATUS = 2
HINT = (
    f'Use the work setup instead: modelSelection {{"instanceId": "{WORK_INSTANCE}", '
    f'"model": "{WORK_MODEL}"}}. Another model of the same {WORK_INSTANCE} instance is fine if '
    "the user named one. Never use the secretary instance for a work thread."
)


def is_secretary(instance_id):
    name = str(instance_id or "")
    return SECRETARY_MARKER in name.lower() or (bool(SECRETARY_INSTANCE) and name == SECRETARY_INSTANCE)


def launch_problem(tool_input):
    selection = tool_input.get("modelSelection") or {}
    if not selection.get("instanceId") and not selection.get("provider"):
        return "The new thread has no model, so it would inherit the secretary's own setup. " + HINT
    if is_secretary(selection.get("instanceId")):
        return "That would make the new thread a secretary thread. " + HINT
    return None


def create_threads_problem(tool_input):
    for thread in tool_input.get("threads") or []:
        target = thread.get("target") or {}
        if not target.get("providerInstanceId") or is_secretary(target.get("providerInstanceId")):
            return (
                "Each new thread needs target.providerInstanceId set to a work instance, not empty "
                f'and not the secretary. Use providerInstanceId "{WORK_INSTANCE}" and model "{WORK_MODEL}".'
            )
    return None


def configure_problem(tool_input):
    selection = tool_input.get("modelSelection") or {}
    if is_secretary(selection.get("instanceId")):
        return "Do not move a work thread onto the secretary instance. " + HINT
    return None


CHECKS = {
    "t3_thread_launch": launch_problem,
    "create_threads": create_threads_problem,
    "t3_thread_configure": configure_problem,
}


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    tool_name = str(payload.get("tool_name", ""))
    check = next((fn for name, fn in CHECKS.items() if tool_name.endswith(name)), None)
    if check is None:
        return 0
    problem = check(payload.get("tool_input") or {})
    if problem is None:
        return 0
    print(problem, file=sys.stderr)
    return BLOCK_EXIT_STATUS


if __name__ == "__main__":
    sys.exit(main())
