def assert_no_new_gateway_errors(before: str, after: str):
    if after.startswith(before):
        new_content = after[len(before):]
    else:
        # File may have rotated/truncated.
        new_content = after

    errors = [
        line
        for line in new_content.splitlines()
        if " ERROR " in line
    ]

    if errors:
        raise AssertionError(
            "Gateway produced ERROR-level entries:\n"
            + "\n".join(errors)
        )