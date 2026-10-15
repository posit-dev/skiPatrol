"""
Typed results for R (sfr_common.py).

The bridge used to flatten a DataFrame to plain lists and let R guess each
column's type from its values: '01234' became the number 1234, dates stayed
text, and a NULL turned a number column into text. These pin the replacement:
every column carries its Snowflake type, and values are text in the SQL API's
formats.
"""
import datetime as dt
from decimal import Decimal

import pandas as pd

import sfr_common as c


def _one(pdf):
    out = c.pandas_to_typed_dict(pdf)
    return out, dict(zip(out["columns"], out["kinds"]))


def test_digit_only_text_is_text_and_keeps_its_zeros():
    out, kinds = _one(pd.DataFrame({"ZIP": ["01234", None, "90210"]}))
    assert kinds["ZIP"]["type"] == "text"
    assert out["data"]["ZIP"] == ["01234", c.NA, "90210"]


def test_numbers_with_nulls_stay_numbers():
    out, kinds = _one(pd.DataFrame({"N": [7, None, 2147483648]}))   # pandas: float64 with NaN
    assert kinds["N"]["type"] == "real"
    assert out["data"]["N"] == ["7.0", c.NA, "2147483648.0"]
    out, kinds = _one(pd.DataFrame({"N": pd.array([7, None, 9], dtype="Int64")}))
    assert kinds["N"]["type"] == "fixed"
    assert out["data"]["N"] == ["7", c.NA, "9"]


def test_dates_times_and_timestamps_use_the_sql_api_formats():
    pdf = pd.DataFrame({
        "D": [dt.date(2026, 10, 14), None],
        "T": [dt.time(12, 34, 56, 500000), None],
        "NTZ": pd.to_datetime(["2026-10-14 12:34:56.123456", None]),
    })
    out, kinds = _one(pdf)
    assert kinds["D"]["type"] == "date" and out["data"]["D"] == ["20740", c.NA]
    assert kinds["T"]["type"] == "time" and out["data"]["T"] == ["45296.500000", c.NA]
    assert kinds["NTZ"]["type"] == "timestamp_ntz"
    assert out["data"]["NTZ"] == ["1791981296.123456", c.NA]


def test_timezone_aware_timestamps_carry_the_session_zone():
    pdf = pd.DataFrame({"L": pd.to_datetime(["2026-03-29 08:30:00"]).tz_localize("UTC").tz_convert("America/Los_Angeles")})
    out, kinds = _one(pdf)
    assert kinds["L"]["type"] == "timestamp_ltz"
    assert out["session_timezone"] == "America/Los_Angeles"
    assert out["data"]["L"] == ["1774773000.000000"]


def test_negative_and_fractional_epochs_are_exact():
    assert c._epoch_text(dt.datetime(1969, 12, 31, 23, 59, 59, 500000)) == "-0.500000"
    assert c._epoch_text(dt.datetime(1970, 1, 1, 0, 0, 0, 1)) == "0.000001"
    assert c._date_text(dt.date(1900, 1, 1)) == "-25567"


def test_booleans_decimals_binary_and_json():
    pdf = pd.DataFrame({
        "B": [True, False, None],
        "DEC": [Decimal("1.50"), Decimal("-2.25"), None],
        "BIN": [b"\xde\xad\xbe\xef", None, b"\x00"],
        "V": [{"a": 1}, None, [1, 2]],
    })
    out, kinds = _one(pdf)
    assert kinds["B"]["type"] == "boolean" and out["data"]["B"] == ["true", "false", c.NA]
    assert kinds["DEC"] == {"type": "fixed", "scale": 2, "precision": 0}
    assert out["data"]["DEC"] == ["1.50", "-2.25", c.NA]
    assert out["data"]["BIN"] == ["DEADBEEF", c.NA, "00"]
    assert out["data"]["V"] == ['{"a": 1}', c.NA, "[1, 2]"]


def test_zero_rows_still_have_types():
    out = c.pandas_to_typed_dict(pd.DataFrame({"A": pd.Series([], dtype="object"), "D": pd.Series([], dtype="float64")}))
    assert out["nrows"] == 0
    assert [k["type"] for k in out["kinds"]] == ["text", "real"]


def test_quoted_column_names_are_cleaned():
    out = c.pandas_to_typed_dict(pd.DataFrame({'"name"': ["a"]}))
    assert out["columns"] == ["name"]


class _Desc:
    def __init__(self, name, type_code, precision=None, scale=None):
        self.name, self.type_code, self.precision, self.scale = name, type_code, precision, scale


class _Cursor:
    def __init__(self, desc, rows, tz_row=None):
        self.description, self._rows, self._tz_row = desc, rows, tz_row
        self._last = None

    def execute(self, sql):
        self._last = sql

    def fetchall(self):
        return self._rows

    def fetchone(self):
        return self._tz_row

    def close(self):
        pass


class _Conn:
    def __init__(self, main, tz_row=None):
        self._main, self._tz = main, tz_row

    def cursor(self):
        # the first cursor runs the query; later ones are the time zone lookup
        if self._main is not None:
            cur, self._main = self._main, None
            return cur
        return _Cursor(None, [], self._tz)


class _Session:
    def __init__(self, conn):
        self.connection = conn


def test_cursor_results_use_snowflakes_own_types():
    from snowflake.connector.constants import FIELD_NAME_TO_ID as ids
    desc = [_Desc("ID", ids["FIXED"], 38, 0), _Desc("ZIP", ids["TEXT"]), _Desc("L", ids["TIMESTAMP_LTZ"], 0, 9)]
    rows = [(7, "01234", dt.datetime(2026, 3, 29, 1, 30, tzinfo=dt.timezone(dt.timedelta(hours=-7)))),
            (None, None, None)]
    out = c.query_to_typed_dict(_Session(_Conn(_Cursor(desc, rows), tz_row=("TIMEZONE", "America/Los_Angeles"))), "select 1")
    assert out["columns"] == ["ID", "ZIP", "L"]
    assert out["kinds"][0] == {"type": "fixed", "scale": 0, "precision": 38}
    assert out["data"]["ZIP"] == ["01234", c.NA]
    assert out["data"]["ID"] == ["7", c.NA]
    assert out["data"]["L"] == ["1774773000.000000", c.NA]
    assert out["session_timezone"] == "America/Los_Angeles"
    assert out["nrows"] == 2


def test_a_statement_with_no_result_set_returns_no_columns():
    out = c.query_to_typed_dict(_Session(_Conn(_Cursor(None, []))), "create table t (a int)")
    assert out == {"columns": [], "kinds": [], "data": {}, "nrows": 0}
