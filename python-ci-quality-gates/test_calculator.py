"""Unit tests for the calculator module."""

import unittest

from calculator import add, divide, modulo, multiply, power, subtract


class TestCalculator(unittest.TestCase):
    """Validate arithmetic results and expected failure handling."""

    def test_add(self) -> None:
        self.assertEqual(add(2, 3), 5)
        self.assertEqual(add(-1, 1), 0)
        self.assertEqual(add(1.5, 2.5), 4.0)

    def test_subtract(self) -> None:
        self.assertEqual(subtract(5, 3), 2)
        self.assertEqual(subtract(0, 5), -5)
        self.assertEqual(subtract(2.5, 1.0), 1.5)

    def test_multiply(self) -> None:
        self.assertEqual(multiply(3, 4), 12)
        self.assertEqual(multiply(-2, 3), -6)
        self.assertEqual(multiply(2.5, 2), 5.0)

    def test_divide(self) -> None:
        self.assertEqual(divide(10, 2), 5)
        self.assertEqual(divide(7, 2), 3.5)

    def test_division_by_zero(self) -> None:
        with self.assertRaisesRegex(ValueError, "Cannot divide by zero"):
            divide(10, 0)

    def test_power(self) -> None:
        self.assertEqual(power(2, 3), 8)
        self.assertEqual(power(5, 0), 1)
        self.assertEqual(power(4, 0.5), 2)

    def test_modulo(self) -> None:
        self.assertEqual(modulo(10, 3), 1)
        self.assertEqual(modulo(8, 4), 0)

    def test_modulo_by_zero(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "Cannot calculate modulo by zero",
        ):
            modulo(10, 0)

    def test_invalid_operand_types(self) -> None:
        with self.assertRaises(TypeError):
            add("2", 3)

        with self.assertRaises(TypeError):
            multiply(2, None)


if __name__ == "__main__":
    unittest.main()
