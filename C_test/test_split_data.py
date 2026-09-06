import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("split_data.py")


class SplitDataTests(unittest.TestCase):
    def load_module(self):
        spec = importlib.util.spec_from_file_location("split_data", SCRIPT)
        if spec is None or spec.loader is None:
            self.fail(f"could not load {SCRIPT}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_consecutive_words_are_distributed_across_four_banks(self):
        module = self.load_module()
        words = [0x11223344, 0x55667788, 0x99AABBCC, 0xDDEEFF00, 0x12345678]
        raw = b"".join(word.to_bytes(4, "little") for word in words)

        banks = module.split_banks(raw)

        self.assertEqual(banks[0], [0x11223344, 0x12345678])
        self.assertEqual(banks[1], [0x55667788])
        self.assertEqual(banks[2], [0x99AABBCC])
        self.assertEqual(banks[3], [0xDDEEFF00])

    def test_partial_final_word_is_zero_padded(self):
        module = self.load_module()
        self.assertEqual(module.split_banks(bytes([0xAA, 0xBB])), [[0x0000BBAA], [], [], []])

    def test_written_hex_is_valid_even_when_section_is_empty(self):
        module = self.load_module()
        with tempfile.TemporaryDirectory() as directory:
            outputs = module.write_banks(b"", Path(directory) / "data")
            self.assertEqual(len(outputs), 4)
            for output in outputs:
                self.assertEqual(output.read_text(), "00000000\n")


if __name__ == "__main__":
    unittest.main()
