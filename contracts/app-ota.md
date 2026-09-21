# A95X Application OTA Contract

Application artifacts for `a95x-f3-air` must be signed, pinned to the declared release channel, and validated against the arm64 runtime ABI. Updates must be atomic and rollback-safe. No runtime package resolver or reusable plaintext credential is permitted on the appliance.
