"""
Snowflake Connection Bridge
============================

Python backend for skiPatrol::R/connect.R.

Handles Snowpark session creation, active session detection
for Workspace Notebooks, and robust pandas → R data conversion.
"""


import os
from typing import Optional


import os as _os
import sys as _sys

_here = _os.path.dirname(_os.path.abspath(__file__))
if _here not in _sys.path:
    _sys.path.insert(0, _here)
from sfr_common import pandas_to_typed_dict, query_to_typed_dict  # noqa: E402


def get_active_session():
    """
    Get the active Snowpark session (works in Workspace Notebooks).

    Returns:
        Snowpark Session object

    Raises:
        Exception if no active session is available
    """
    from snowflake.snowpark.context import get_active_session
    return get_active_session()


def _load_private_key(key_path: str) -> bytes:
    """
    Load a PEM private key file and return the DER-encoded bytes.

    Snowpark Session.builder requires the private key as DER bytes
    in the 'private_key' parameter.

    Args:
        key_path: Path to PEM-encoded private key (.p8 file)

    Returns:
        DER-encoded private key bytes
    """
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.backends import default_backend

    key_path = os.path.expanduser(key_path)
    with open(key_path, "rb") as f:
        key_data = f.read()

    private_key = serialization.load_pem_private_key(
        key_data,
        password=None,
        backend=default_backend(),
    )

    return private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def create_session(
    account: Optional[str] = None,
    user: Optional[str] = None,
    warehouse: Optional[str] = None,
    database: Optional[str] = None,
    schema: Optional[str] = None,
    role: Optional[str] = None,
    authenticator: Optional[str] = None,
    private_key_file: Optional[str] = None,
    connection_name: Optional[str] = None,
    **kwargs,
):
    """
    Create a new Snowpark session, either from explicit parameters or by
    name from connections.toml.

    Supports multiple auth methods:
    - Key-pair (SNOWFLAKE_JWT): pass private_key_file path
    - External browser: authenticator="externalbrowser"
    - Username/password: authenticator="snowflake" + password in kwargs
    - Named connection (connection_name): the connector reads account and
      credentials from connections.toml itself, including an OAuth token
      written there directly -- the shape Posit Workbench and the Native
      App use. Only this path can consume that shape: it has no `token`
      parameter, so a caller with just an account/user/authenticator
      cannot express "authenticate with this connections.toml token"
      without connection_name. This also means the token is never passed
      through this bridge at all, and the connector owns re-reading it on
      rotation rather than this session holding a copy that goes stale.

    Args:
        account: Snowflake account identifier. Not needed (and ignored
            for auth purposes) when connection_name is given.
        user: Username
        warehouse: Default warehouse -- overrides the named connection's,
            if both are given
        database: Default database -- overrides the named connection's
        schema: Default schema -- overrides the named connection's
        role: Role to use -- overrides the named connection's
        authenticator: Authentication method
        private_key_file: Path to PEM private key (.p8 file)
        connection_name: Profile name in connections.toml. When given,
            takes priority: the connector resolves everything else
            (account, credentials) from that profile, with any of
            warehouse/database/schema/role passed here overriding it.
        **kwargs: Additional connection parameters

    Returns:
        Snowpark Session object
    """
    from snowflake.snowpark import Session

    if connection_name:
        conn_params = {"connection_name": connection_name}
        if warehouse:
            conn_params["warehouse"] = warehouse
        if database:
            conn_params["database"] = database
        if schema:
            conn_params["schema"] = schema
        if role:
            conn_params["role"] = role
        conn_params.update(kwargs)
        return Session.builder.configs(conn_params).create()

    if not account:
        raise ValueError("create_session() requires either connection_name or account")

    conn_params = {"account": account}

    if user:
        conn_params["user"] = user
    if warehouse:
        conn_params["warehouse"] = warehouse
    if database:
        conn_params["database"] = database
    if schema:
        conn_params["schema"] = schema
    if role:
        conn_params["role"] = role

    # Handle key-pair authentication
    if private_key_file:
        conn_params["private_key"] = _load_private_key(private_key_file)
        # Don't pass authenticator for key-pair; Snowpark auto-detects
    elif authenticator:
        conn_params["authenticator"] = authenticator

    conn_params.update(kwargs)

    session = Session.builder.configs(conn_params).create()
    return session


def pandas_to_r_dict(pdf):
    """
    Convert a pandas DataFrame to a column-oriented Python dict
    with native Python types (no numpy arrays).

    Uses Series.tolist() which converts numpy scalars to native
    Python types (int, float, str) inside NumPy's own C code,
    avoiding the NumPy 1.x/2.x ABI mismatch that occurs when
    reticulate tries to read numpy arrays directly.

    Args:
        pdf: A pandas DataFrame.

    Returns:
        dict[str, list]: Column name → list of native Python values.
    """
    cols = list(pdf.columns)
    return {col: pdf[col].tolist() for col in cols}


def generate_jwt_token(session) -> str:
    """Generate a JWT token from the session's key-pair credentials.

    Extracts the private key from the Snowpark session's connection
    and generates a short-lived JWT suitable for SPCS REST endpoint
    authentication.

    Args:
        session: Snowpark Session object (must use key-pair auth).

    Returns:
        JWT token string.

    Raises:
        RuntimeError: if the session doesn't use key-pair auth or
            the token cannot be generated.
    """
    import hashlib
    import base64
    import time

    try:
        import jwt as pyjwt
    except ImportError:
        raise RuntimeError(
            "PyJWT package is required for JWT generation. "
            "Install with: pip install PyJWT"
        )
    from cryptography.hazmat.primitives import serialization

    # Navigate to the underlying connector to extract credentials.
    # The Snowpark connector stores the private key as DER bytes
    # on conn_obj._private_key after key-pair authentication.
    try:
        conn_obj = session._conn._conn
        pk_data = getattr(conn_obj, "_private_key", None)
    except AttributeError:
        pk_data = None

    if pk_data is None:
        raise RuntimeError(
            "Cannot extract private key from session. "
            "This connection may not use key-pair authentication."
        )

    # pk_data is DER-encoded bytes -- load into a cryptography key object
    from cryptography.hazmat.backends import default_backend

    if isinstance(pk_data, bytes):
        pk = serialization.load_der_private_key(
            pk_data, password=None, backend=default_backend()
        )
    else:
        raise RuntimeError(
            f"Unexpected private key type: {type(pk_data)}. "
            "Expected DER-encoded bytes."
        )

    pub = pk.public_key()

    pub_der = pub.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    fp = base64.standard_b64encode(
        hashlib.sha256(pub_der).digest()
    ).decode("utf-8")

    # Get account and user from the session
    account = (
        session.get_current_account()
        .strip('"')
        .upper()
        .replace(".", "-")
    )
    user = session.get_current_user().strip('"').upper()

    now = int(time.time())
    payload = {
        "iss": f"{account}.{user}.SHA256:{fp}",
        "sub": f"{account}.{user}",
        "iat": now,
        "exp": now + 3600,
    }

    return pyjwt.encode(payload, pk, algorithm="RS256")


def query_to_dict(session, sql):
    """
    Execute a SQL query and return the result as a column-oriented dict
    with native Python types only (safe for reticulate conversion to R).

    The result carries each column's Snowflake type, scale and precision
    ("kinds") and its values as text in the SQL API's formats, so R rebuilds
    the right types instead of guessing them from the values; see
    sfr_common.py. The query runs on the Snowpark session's own connection,
    so session state (current schema, temporary tables, query tag) applies.
    Keeps the entire pandas/numpy interaction on the Python side, avoiding
    reticulate's NumPy version checks which can fail with NumPy 1.x/2.x ABI
    mismatches.

    NULL is the string "NA_SENTINEL_" so R's as.data.frame() sees consistent
    column lengths; the R side turns it into NA.

    Args:
        session: Snowpark Session object.
        sql: SQL query string.

    Returns:
        dict with keys:
            - "columns": list of column names
            - "kinds": list, one per column, of {type, scale, precision}
            - "data": dict[str, list[str]] of column name -> values as text
            - "nrows": int
            - "session_timezone": str, only if a column is TIMESTAMP_LTZ/TZ
    """
    try:
        session.connection
    except AttributeError:
        # A session object without a connection (very old Snowpark): fall
        # back to pandas, which infers types from the values.
        return pandas_to_typed_dict(session.sql(sql).to_pandas())
    return query_to_typed_dict(session, sql)
