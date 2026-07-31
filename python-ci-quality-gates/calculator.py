"""Arithmetic operations used to demonstrate automated CI validation."""

from numbers import Real


def _validate_number(value: Real, name: str) -> None:
    """Ensure a supplied operand is a real number."""
    if not isinstance(value, Real):
        raise TypeError(f"{name} must be a real number")


def add(a: Real, b: Real) -> Real:
    """Return the sum of two numbers."""
    _validate_number(a, "a")
    _validate_number(b, "b")
    return a + b


def subtract(a: Real, b: Real) -> Real:
    """Subtract b from a."""
    _validate_number(a, "a")
    _validate_number(b, "b")
    return a - b


def multiply(a: Real, b: Real) -> Real:
    """Return the product of two numbers."""
    _validate_number(a, "a")
    _validate_number(b, "b")
    return a * b


def divide(a: Real, b: Real) -> float:
    """Divide a by b and reject division by zero."""
    _validate_number(a, "a")
    _validate_number(b, "b")

    if b == 0:
        raise ValueError("Cannot divide by zero")

    return a / b


def power(a: Real, b: Real) -> Real:
    """Raise a to the power of b."""
    _validate_number(a, "a")
    _validate_number(b, "b")
    return a**b


def modulo(a: Real, b: Real) -> Real:
    """Return the remainder after dividing a by b."""
    _validate_number(a, "a")
    _validate_number(b, "b")

    if b == 0:
        raise ValueError("Cannot calculate modulo by zero")

    return a % b
