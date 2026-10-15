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
    if isinstance(v, float) and v.is_integer():
        # pandas turns an integer column that has NULLs into float64
        return str(int(v))
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


def pandas_to_typed_dict(pdf, kinds=None):
    """Column-oriented dict for R from a pandas DataFrame; see module docs.

    `kinds` is an optional list, one entry per column, of Snowflake types
    (from DESCRIBE RESULT); an entry that is None, or a missing list, means
    the type is inferred from the pandas dtype and values instead.
    """
    cols = [str(c).strip('"') for c in pdf.columns]
    pdf.columns = cols
    nrows = len(pdf)

    inferred = [_kind_from_series(pdf[c]) for c in cols]
    if kinds is None or len(kinds) != len(cols):
        kinds = inferred
    else:
        kinds = [k if k is not None else i for k, i in zip(kinds, inferred)]
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


# ---------------------------------------------------------------------------
# From a Snowpark DataFrame (Snowflake's types via DESCRIBE RESULT)
# ---------------------------------------------------------------------------

_DESCRIBE_TYPES = {
    "number": "fixed", "decimal": "fixed", "numeric": "fixed", "int": "fixed",
    "integer": "fixed", "bigint": "fixed", "smallint": "fixed", "tinyint": "fixed",
    "byteint": "fixed",
    "float": "real", "double": "real", "real": "real",
    "varchar": "text", "string": "text", "text": "text", "char": "text",
    "character": "text",
    "boolean": "boolean", "date": "date", "time": "time",
    "timestamp_ntz": "timestamp_ntz", "timestamp_ltz": "timestamp_ltz",
    "timestamp_tz": "timestamp_tz", "timestamp": "timestamp_ntz",
    "binary": "binary", "variant": "text", "object": "text", "array": "text",
    "geography": "text", "geometry": "text", "vector": "text",
}


def _kind_from_describe_type(type_text):
    """Parse a DESCRIBE RESULT type such as NUMBER(38,0) or TIMESTAMP_LTZ(9).

    Returns None for a type it does not know, so the caller infers it instead.
    """
    import re
    m = re.match(r"^\s*([A-Za-z_]+)\s*(?:\(\s*(\d+)\s*(?:,\s*(\d+)\s*)?\))?", str(type_text))
    if not m:
        return None
    base = _DESCRIBE_TYPES.get(m.group(1).lower())
    if base is None:
        return None
    first = int(m.group(2)) if m.group(2) else 0
    second = int(m.group(3)) if m.group(3) else 0
    if base == "fixed":
        return _kind("fixed", second, first)        # NUMBER(precision, scale)
    if base in ("time",) or base.startswith("timestamp"):
        return _kind(base, first or 9, 0)           # TIME(9): the digit is the scale
    return _kind(base)


def _describe_kinds(session, query_id, ncols):
    """Snowflake's own column types for a query already run, or None."""
    try:
        rows = session.sql("DESCRIBE RESULT '%s'" % query_id).collect()
        if len(rows) != ncols:
            return None
        return [_kind_from_describe_type(r["type"]) for r in rows]
    except Exception:
        return None


def snowpark_to_typed_dict(df):
    """Typed dict for R from a Snowpark DataFrame.

    pandas hides Snowflake's precision: every whole-number column is int64
    (or float64 if it has NULLs), and Snowpark's own schema reports LongType
    for every scale-0 NUMBER. So the query that produces the DataFrame is
    recorded, and DESCRIBE RESULT is asked for the real types. If that is
    not possible for any reason, the types are inferred from the pandas
    result, as before.
    """
    session = df.session
    kinds = None
    try:
        with session.query_history() as history:
            pdf = df.to_pandas()
        if history.queries:
            kinds = _describe_kinds(session, history.queries[-1].query_id, len(pdf.columns))
    except AttributeError:
        # No query history on this Snowpark version: just fetch.
        pdf = df.to_pandas()
    return pandas_to_typed_dict(pdf, kinds=kinds)
