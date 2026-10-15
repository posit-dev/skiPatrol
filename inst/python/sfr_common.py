"""Typed query results for R.

Every bridge function that returns a table to R used to flatten a pandas
DataFrame into plain Python lists, which discards Snowflake's column types.
R then guessed each column's type from its values: digit-only text such as
'01234' became the number 1234, dates stayed text, and a column's type changed
if it held a NULL (the NULL was a string, so the whole column became text and
was guessed back).

These helpers keep the type. Each result carries, for every column, the
Snowflake type with its scale and precision ("kinds"), and the values as text
in the formats the Snowflake SQL API uses (epoch days for DATE, seconds for
TIME, epoch seconds for timestamps, "true"/"false" for BOOLEAN), with the
string "NA_SENTINEL_" for NULL. R converts them back with the same rules as
the skiLift package (R/bridge_types.R). Native Python types only: numpy and
pandas objects never reach reticulate, which avoids its NumPy ABI problems.
"""

import datetime as _dt
import json as _json
from decimal import Decimal as _Decimal

NA = "NA_SENTINEL_"

_EPOCH_DATE = _dt.date(1970, 1, 1)
_EPOCH_DT = _dt.datetime(1970, 1, 1, tzinfo=_dt.timezone.utc)

_TIMESTAMP_TYPES = ("timestamp_ntz", "timestamp_ltz", "timestamp_tz", "timestamp")


def _kind(type_, scale=0, precision=0):
    return {"type": type_, "scale": int(scale or 0), "precision": int(precision or 0)}


def _micros_text(total_micro):
    sign = "-" if total_micro < 0 else ""
    m = abs(total_micro)
    return "%s%d.%06d" % (sign, m // 1000000, m % 1000000)


def _epoch_text(v):
    """Seconds since 1970-01-01 UTC as exact text; naive values are taken as UTC."""
    if v.tzinfo is None:
        v = v.replace(tzinfo=_dt.timezone.utc)
    d = v - _EPOCH_DT
    return _micros_text((d.days * 86400 + d.seconds) * 1000000 + d.microseconds)


def _time_text(v):
    return "%d.%06d" % (v.hour * 3600 + v.minute * 60 + v.second, v.microsecond)


def _date_text(v):
    if isinstance(v, _dt.datetime):
        v = v.date()
    return str((v - _EPOCH_DATE).days)


def _fixed_text(v):
    if isinstance(v, _Decimal):
        return format(v, "f")
    return str(int(v)) if isinstance(v, int) else str(v)


def _format_value(type_, v):
    if type_ == "fixed":
        return _fixed_text(v)
    if type_ in ("real", "float"):
        return repr(float(v))
    if type_ == "boolean":
        return "true" if v else "false"
    if type_ == "date":
        return _date_text(v)
    if type_ == "time":
        return _time_text(v)
    if type_ in _TIMESTAMP_TYPES:
        return _epoch_text(v)
    if type_ == "binary":
        return bytes(v).hex().upper()
    if isinstance(v, (dict, list)):
        return _json.dumps(v)
    return str(v)


def column_text(values, type_):
    """Format one column; None becomes the NULL marker."""
    return [NA if v is None else _format_value(type_, v) for v in values]


def _result(columns, kinds, data, nrows, session_timezone=None):
    out = {"columns": list(columns), "kinds": kinds, "data": data, "nrows": nrows}
    if session_timezone:
        out["session_timezone"] = session_timezone
    return out


# ---------------------------------------------------------------------------
# From a pandas DataFrame (types inferred from the dtypes and values)
# ---------------------------------------------------------------------------

def _kind_from_series(series):
    """Best-effort Snowflake type for a pandas column. Whole numbers carry
    precision 0 (unknown), which R treats as large, as it does NUMBER(38,0)."""
    import pandas as pd

    dtype = series.dtype
    if pd.api.types.is_bool_dtype(dtype):
        return _kind("boolean")
    if pd.api.types.is_integer_dtype(dtype):
        return _kind("fixed")
    if pd.api.types.is_float_dtype(dtype):
        return _kind("real")
    if isinstance(dtype, pd.DatetimeTZDtype):
        return _kind("timestamp_ltz", 9)
    if pd.api.types.is_datetime64_any_dtype(dtype):
        return _kind("timestamp_ntz", 9)

    first = next((v for v in series if v is not None and not _is_missing(v)), None)
    if first is None or isinstance(first, str):
        return _kind("text")
    if isinstance(first, bool):
        return _kind("boolean")
    if isinstance(first, _dt.datetime):
        return _kind("timestamp_ltz" if first.tzinfo else "timestamp_ntz", 9)
    if isinstance(first, _dt.date):
        return _kind("date")
    if isinstance(first, _dt.time):
        return _kind("time", 9)
    if isinstance(first, (bytes, bytearray)):
        return _kind("binary")
    if isinstance(first, _Decimal):
        exp = first.as_tuple().exponent
        return _kind("fixed", max(0, -exp) if isinstance(exp, int) else 0)
    if isinstance(first, int):
        return _kind("fixed")
    if isinstance(first, float):
        return _kind("real")
    return _kind("text")


def _is_missing(v):
    try:
        import pandas as pd
        return bool(pd.isna(v))
    except (TypeError, ValueError):
        return False


def pandas_to_typed_dict(pdf):
    """Column-oriented dict for R from a pandas DataFrame; see module docs."""
    cols = [str(c).strip('"') for c in pdf.columns]
    pdf.columns = cols
    nrows = len(pdf)

    kinds = [_kind_from_series(pdf[c]) for c in cols]
    session_tz = None
    for c, k in zip(cols, kinds):
        if k["type"] == "timestamp_ltz" and session_tz is None:
            tz = getattr(pdf[c].dtype, "tz", None)
            session_tz = str(tz) if tz is not None else None

    if nrows == 0:
        return _result(cols, kinds, {c: [] for c in cols}, 0, session_tz)

    data = {}
    for c, k in zip(cols, kinds):
        mask = pdf[c].isna().tolist()
        vals = pdf[c].tolist()
        data[c] = column_text([None if m else v for v, m in zip(vals, mask)], k["type"])
    return _result(cols, kinds, data, nrows, session_tz)


# ---------------------------------------------------------------------------
# From the connector cursor (types are Snowflake's own, with scale/precision)
# ---------------------------------------------------------------------------

def _type_name(type_code):
    from snowflake.connector.constants import FIELD_ID_TO_NAME
    return FIELD_ID_TO_NAME.get(type_code, "TEXT").lower()


def _session_timezone(connection):
    cur = connection.cursor()
    try:
        cur.execute("SHOW PARAMETERS LIKE 'TIMEZONE' IN SESSION")
        row = cur.fetchone()
        return str(row[1]) if row else None
    finally:
        cur.close()


def query_to_typed_dict(session, sql):
    """Run `sql` on the session's own connection and return a typed dict.

    Uses the Snowpark session's connection so session state (current schema,
    temporary tables, query tag) applies exactly as it does for any other call.
    """
    connection = session.connection
    cur = connection.cursor()
    try:
        cur.execute(sql)
        desc = cur.description or []
        rows = cur.fetchall() if desc else []
    finally:
        cur.close()

    names = [d.name.strip('"') for d in desc]
    kinds = [_kind(_type_name(d.type_code), d.scale, d.precision) for d in desc]
    data = {n: column_text([r[i] for r in rows], kinds[i]["type"]) for i, n in enumerate(names)}

    tz = None
    if any(k["type"] in ("timestamp_ltz", "timestamp_tz") for k in kinds):
        tz = _session_timezone(connection)
    return _result(names, kinds, data, len(rows), tz)
