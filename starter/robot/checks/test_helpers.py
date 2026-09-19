"""Offline regression checks for Robot helpers (no vehicle commands)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'libraries'))
from gateway_log import assert_heartbeat_sequence_timing, get_json_value_as_integer
from log_validation import assert_no_new_gateway_errors


def heartbeat(t, seq, latency=10):
    return (f'2026-09-19T12:00:00Z {t:.3f} TCU1 TCU HB DEBUG '
            f'0x0001 heartbeat ok seq={seq} latency_ms={latency}\n')


class HelpersTest(unittest.TestCase):
    def test_nominal_heartbeats_and_restart(self):
        log = heartbeat(10.010, 1) + heartbeat(12.030, 2, 30)
        log += heartbeat(1.010, 1) + heartbeat(3.010, 2)
        self.assertEqual(assert_heartbeat_sequence_timing(log), 2)

    def test_bad_period_and_insufficient_samples_fail(self):
        for log in ('', heartbeat(1, 1), heartbeat(1, 1) + heartbeat(4, 2)):
            with self.subTest(log=log), self.assertRaises(AssertionError):
                assert_heartbeat_sequence_timing(log)

    def test_calibration_integer_is_not_silently_coerced(self):
        self.assertEqual(get_json_value_as_integer('{"deadline": 600}', 'deadline'), 600)
        for value in ('true', '600.5', '"600"'):
            with self.assertRaises(AssertionError):
                get_json_value_as_integer('{"deadline": ' + value + '}', 'deadline')

    def test_only_new_errors_fail(self):
        before = 'old ERROR failure\n'
        assert_no_new_gateway_errors(before, before + 'new INFO ok\n')
        with self.assertRaises(AssertionError):
            assert_no_new_gateway_errors(before, before + 'new ERROR failure\n')


if __name__ == '__main__':
    unittest.main()
