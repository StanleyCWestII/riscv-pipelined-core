# T18: ecall reports cause 01, drains older work, and freezes Fetch in place.
    addi x1, x0, 7            # already in Execute when ecall reaches Decode
    ecall
    addi x2, x0, 1            # must not execute
