// Package token defines constants representing the lexical tokens of T-SQL.
package token

// Type represents the type of a lexical token.
type Type int

const (
	// Special tokens
	ILLEGAL Type = iota
	EOF
	COMMENT

	// Identifiers and literals
	IDENT       // table_name, column_name
	VARIABLE    // @variable
	TEMPVAR     // @@global_variable
	SYSVAR      // $action, $identity, etc.
	INT         // 12345
	FLOAT       // 123.45
	MONEY_LIT   // $123.45
	STRING      // 'string literal'
	NSTRING     // N'unicode string'
	BINARY      // 0x1234ABCD
	PLACEHOLDER // ? (parameter placeholder)

	// Operators
	PLUS      // +
	MINUS     // -
	ASTERISK  // *
	SLASH     // /
	PERCENT   // %
	AMPERSAND // &
	PIPE      // |
	CARET     // ^
	LSHIFT    // <<
	RSHIFT    // >>
	TILDE     // ~
	EQ        // =
	NEQ       // <> or !=
	LT        // <
	GT        // >
	LTE       // <=
	NOT_LT    // !< (not less than, same as >=)
	NOT_GT    // !> (not greater than, same as <=)
	GTE       // >=
	PLUSEQ    // +=
	MINUSEQ   // -=
	MULEQ     // *=
	DIVEQ     // /=
	MODEQ     // %=
	ANDEQ     // &=
	OREQ      // |=
	XOREQ     // ^=
	CONCAT    // + (string concatenation, same as PLUS)
	SCOPE     // ::

	// Delimiters
	COMMA     // ,
	SEMICOLON // ;
	LPAREN    // (
	RPAREN    // )
	LBRACKET  // [
	RBRACKET  // ]
	DOT       // .
	COLON     // :

	keyword_beg
	// Keywords - DDL
	CREATE
	ALTER
	DROP
	TRUNCATE
	TABLE
	VIEW
	INDEX
	PROCEDURE
	PROC
	FUNCTION
	TRIGGER
	REPLICATION
	SCHEMA
	DATABASE
	SERVER
	CONSTRAINT
	PRIMARY
	FOREIGN
	KEY
	REFERENCES
	UNIQUE
	CLUSTERED
	NONCLUSTERED
	IDENTITY
	ROWGUIDCOL
	SPARSE
	CASCADE
	RESTRICT
	ACTION
	COLLATE
	PERSISTED
	ADD
	COLUMN
	RENAME
	CHECK
	NOCHECK
	DEFAULT_KW
	// Additional DDL keywords
	RETURNS
	INCLUDE
	SCHEMABINDING
	INSTEAD
	AFTER
	OF

	// Keywords - DML
	SELECT
	INSERT
	UPDATE
	DELETE
	MERGE
	USING
	MATCHED
	TARGET
	SOURCE
	INTO
	VALUES
	VALUE
	FROM
	WHERE
	SET
	OUTPUT
	READONLY

	// Keywords - Query clauses
	JOIN
	INNER
	LEFT
	RIGHT
	FULL
	OUTER
	CROSS
	HASH
	LOOP
	REMOTE
	APPLY
	ON
	AND
	OR
	NOT
	IN
	EXISTS
	BETWEEN
	LIKE
	ESCAPE
	IS
	NULL
	AS
	DISTINCT
	ALL
	TOP
	PERCENT_KW // PERCENT as keyword
	WITH
	TIES
	ORDER
	BY
	ASC
	DESC
	GROUP
	GROUPING
	CUBE
	ROLLUP
	HAVING
	UNION
	INTERSECT
	EXCEPT
	OFFSET
	FETCH
	NEXT
	ROWS
	ONLY
	FIRST
	LAST
	PRIOR
	ABSOLUTE
	RELATIVE
	WITHIN
	// Window frame tokens
	RANGE
	UNBOUNDED
	PRECEDING
	FOLLOWING
	CURRENT
	ROW
	PIVOT
	UNPIVOT
	FOR
	OPTION

	// Keywords - Control flow
	IF
	ELSE
	BEGIN
	END
	END_CONVERSATION
	NEXT_VALUE_FOR        // NEXT VALUE FOR sequence
	XML_SCHEMA_COLLECTION // XML SCHEMA COLLECTION
	ASYMMETRIC_KEY        // ASYMMETRIC KEY (for GRANT)
	SYMMETRIC_KEY         // SYMMETRIC KEY (for GRANT)
	TRUNCATE_TABLE        // TRUNCATE TABLE
	WITH_PARTITIONS       // WITH (PARTITIONS ...)
	WITH_XMLNAMESPACES    // WITH XMLNAMESPACES
	WITH_CHECK            // WITH CHECK
	WITH_NOCHECK          // WITH NOCHECK
	APPLICATION_ROLE      // APPLICATION ROLE
	CREATE_RULE           // CREATE RULE
	BEGIN_ATOMIC          // BEGIN ATOMIC (natively compiled)
	IS_DISTINCT_FROM      // IS DISTINCT FROM
	IS_NOT_DISTINCT_FROM  // IS NOT DISTINCT FROM
	WHILE
	BREAK
	CONTINUE
	RETURN
	GOTO
	WAITFOR
	DELAY
	TIME
	TRY
	CATCH
	THROW
	RAISERROR

	// Keywords - Variables and types
	DECLARE
	CURSOR
	OPEN
	CLOSE
	FETCH_KW
	DEALLOCATE
	LOCAL
	GLOBAL
	FORWARD_ONLY
	SCROLL
	STATIC
	KEYSET
	DYNAMIC
	FAST_FORWARD
	READ_ONLY
	SCROLL_LOCKS
	OPTIMISTIC
	TYPE_WARNING

	// Keywords - Transactions
	TRANSACTION
	TRAN
	COMMIT
	ROLLBACK
	SAVE
	SAVEPOINT
	ISOLATION
	LEVEL
	SNAPSHOT

	// Keywords - Execution
	EXEC
	EXECUTE
	PRINT
	USE

	// Keywords - Table expressions
	CTE // Common Table Expression
	RECURSIVE
	OVER
	PARTITION
	ROW_NUMBER
	RANK
	DENSE_RANK
	NTILE
	LAG
	LEAD
	FIRST_VALUE
	LAST_VALUE

	// Keywords - Case expression
	CASE
	WHEN
	THEN
	COALESCE
	NULLIF
	IIF

	// Keywords - Type conversion
	CAST
	CONVERT
	TRY_CAST
	TRY_CONVERT
	PARSE
	TRY_PARSE
	TRIM

	// Keywords - Aggregate functions (treated as keywords for parsing)
	COUNT
	SUM
	AVG
	MIN
	MAX

	// Keywords - Data types
	INT_TYPE
	BIGINT
	SMALLINT
	TINYINT
	BIT
	DECIMAL
	NUMERIC
	MONEY
	SMALLMONEY
	FLOAT_TYPE
	REAL
	DATE
	DATETIME
	DATETIME2
	SMALLDATETIME
	DATETIMEOFFSET
	TIME_TYPE
	CHAR
	VARCHAR
	TEXT
	NCHAR
	NVARCHAR
	NTEXT
	BINARY_TYPE
	VARBINARY
	IMAGE
	UNIQUEIDENTIFIER
	XML
	JSON
	SQL_VARIANT
	HIERARCHYID
	GEOMETRY
	GEOGRAPHY
	ROWVERSION
	TIMESTAMP

	// Keywords - FOR XML/JSON
	RAW
	AUTO
	PATH
	EXPLICIT
	ELEMENTS
	ROOT
	TYPE_DIRECTIVE
	WITHOUT_ARRAY_WRAPPER
	INCLUDE_NULL_VALUES

	// Keywords - ALTER INDEX / BULK INSERT
	REBUILD
	REORGANIZE
	BULK
	RECOMPILE

	// Keywords - Temporal tables
	GENERATED
	ALWAYS
	SYSTEM_TIME
	PERIOD
	CONTAINED
	SYSTEM_VERSIONING
	TO
	START

	// Keywords - Misc
	GO
	NOCOUNT
	OFFSETS
	XACT_ABORT
	ANSI_NULLS
	QUOTED_IDENTIFIER
	NOLOCK
	HOLDLOCK
	UPDLOCK
	TABLOCK
	TABLOCKX
	ROWLOCK
	READPAST
	READCOMMITTED
	READUNCOMMITTED
	REPEATABLEREAD
	SERIALIZABLE

	// Keywords - Additional SET options
	ANSI_WARNINGS
	ARITHABORT
	ARITHIGNORE
	ANSI_DEFAULTS
	CONCAT_NULL_YIELDS_NULL
	NUMERIC_ROUNDABORT
	ANSI_PADDING
	ANSI_NULL_DFLT_ON
	CURSOR_CLOSE_ON_COMMIT
	IMPLICIT_TRANSACTIONS
	FMTONLY
	PARSEONLY
	FORCEPLAN
	SHOWPLAN_TEXT
	SHOWPLAN_ALL
	SHOWPLAN_XML
	NOEXEC
	REMOTE_PROC_TRANSACTIONS
	STATISTICS
	CONTEXT_INFO
	DEADLOCK_PRIORITY
	NOWAIT

	// Keywords - Stage 2 additions
	HINT
	ZONE
	TABLESAMPLE
	ENABLE
	DISABLE
	AT

	// Keywords - Stage 3 additions
	SYNONYM
	REVERT
	OPENJSON
	CALLER
	OWNER_KW
	SELF
	USER

	// Keywords - Stage 4 additions
	SEQUENCE
	INCREMENT
	MINVALUE
	MAXVALUE
	CYCLE
	CACHE_KW
	DBCC

	// Keywords - Stage 5 additions
	GRANT
	REVOKE
	DENY
	LOGIN
	ROLE
	MEMBER
	PASSWORD
	WINDOW
	WINDOWS
	WITHOUT
	AUTHORIZATION
	BACKUP
	RESTORE
	DISK
	LOG
	COMPRESSION
	INIT
	NORECOVERY
	RECOVERY
	FILELISTONLY
	HEADERONLY
	COPY_ONLY
	CERTIFICATE
	DIFFERENTIAL
	STATS
	MEDIANAME
	MEDIADESCRIPTION
	BLOCKSIZE
	BUFFERCOUNT
	MAXTRANSFERSIZE
	CHECKSUM
	NO_CHECKSUM
	CONTINUE_AFTER_ERROR
	STOP_ON_ERROR
	// Cryptography tokens
	MASTER
	SYMMETRIC
	ASYMMETRIC
	ENCRYPTION
	DECRYPTION
	ALGORITHM
	SUBJECT
	// CLR tokens
	ASSEMBLY
	PERMISSION_SET
	SAFE
	EXTERNAL_ACCESS
	UNSAFE
	// Partitioning tokens
	SCHEME
	SPLIT
	USED
	// Full-text search tokens
	CONTAINS
	FREETEXT
	CONTAINSTABLE
	FREETEXTTABLE
	FULLTEXT
	CATALOG
	LANGUAGE
	STOPLIST
	// Resource Governor tokens
	RESOURCE
	POOL
	WORKLOAD
	GOVERNOR
	CLASSIFIER
	RECONFIGURE
	// Availability Group tokens
	AVAILABILITY
	REPLICA
	ENDPOINT_URL
	FAILOVER
	SYNCHRONOUS_COMMIT
	ASYNCHRONOUS_COMMIT
	PRIMARY_ROLE
	SECONDARY_ROLE
	LISTENER
	// Service Broker tokens
	MESSAGE
	CONTRACT
	QUEUE
	SERVICE
	DIALOG
	CONVERSATION
	VALIDATION
	WELL_FORMED_XML
	EMPTY
	INITIATOR
	SENT
	ACTIVATION
	RETENTION
	POISON_MESSAGE_HANDLING
	RECEIVE
	SEND
	GET_CONVERSATION
	MOVE
	GET
	RESULT
	UNDEFINED
	NONE_KW
	SETS

	keyword_end
)

var tokenNames = map[Type]string{
	ILLEGAL:               "ILLEGAL",
	EOF:                   "EOF",
	COMMENT:               "COMMENT",
	IDENT:                 "IDENT",
	VARIABLE:              "VARIABLE",
	TEMPVAR:               "TEMPVAR",
	SYSVAR:                "SYSVAR",
	INT:                   "INT",
	FLOAT:                 "FLOAT",
	MONEY_LIT:             "MONEY_LIT",
	STRING:                "STRING",
	NSTRING:               "NSTRING",
	BINARY:                "BINARY",
	PLACEHOLDER:           "PLACEHOLDER",
	PLUS:                  "+",
	MINUS:                 "-",
	ASTERISK:              "*",
	SLASH:                 "/",
	PERCENT:               "%",
	AMPERSAND:             "&",
	PIPE:                  "|",
	CARET:                 "^",
	LSHIFT:                "<<",
	RSHIFT:                ">>",
	TILDE:                 "~",
	EQ:                    "=",
	NEQ:                   "<>",
	LT:                    "<",
	GT:                    ">",
	LTE:                   "<=",
	NOT_LT:                "!<",
	NOT_GT:                "!>",
	GTE:                   ">=",
	PLUSEQ:                "+=",
	MINUSEQ:               "-=",
	MULEQ:                 "*=",
	DIVEQ:                 "/=",
	MODEQ:                 "%=",
	ANDEQ:                 "&=",
	OREQ:                  "|=",
	XOREQ:                 "^=",
	SCOPE:                 "::",
	COMMA:                 ",",
	SEMICOLON:             ";",
	LPAREN:                "(",
	RPAREN:                ")",
	LBRACKET:              "[",
	RBRACKET:              "]",
	DOT:                   ".",
	COLON:                 ":",
	END_CONVERSATION:      "END_CONVERSATION",
	NEXT_VALUE_FOR:        "NEXT_VALUE_FOR",
	XML_SCHEMA_COLLECTION: "XML_SCHEMA_COLLECTION",
	ASYMMETRIC_KEY:        "ASYMMETRIC_KEY",
	SYMMETRIC_KEY:         "SYMMETRIC_KEY",
	TRUNCATE_TABLE:        "TRUNCATE_TABLE",
	WITH_PARTITIONS:       "WITH_PARTITIONS",
	WITH_XMLNAMESPACES:    "WITH_XMLNAMESPACES",
	WITH_CHECK:            "WITH_CHECK",
	WITH_NOCHECK:          "WITH_NOCHECK",
	APPLICATION_ROLE:      "APPLICATION_ROLE",
	CREATE_RULE:           "CREATE_RULE",
	BEGIN_ATOMIC:          "BEGIN_ATOMIC",
	IS_DISTINCT_FROM:      "IS_DISTINCT_FROM",
	IS_NOT_DISTINCT_FROM:  "IS_NOT_DISTINCT_FROM",
}

var keywords = map[string]Type{
	"CREATE":                   CREATE,
	"ALTER":                    ALTER,
	"DROP":                     DROP,
	"TRUNCATE":                 TRUNCATE,
	"TABLE":                    TABLE,
	"VIEW":                     VIEW,
	"INDEX":                    INDEX,
	"PROCEDURE":                PROCEDURE,
	"PROC":                     PROC,
	"FUNCTION":                 FUNCTION,
	"TRIGGER":                  TRIGGER,
	"REPLICATION":              REPLICATION,
	"SCHEMA":                   SCHEMA,
	"DATABASE":                 DATABASE,
	"SERVER":                   SERVER,
	"CONSTRAINT":               CONSTRAINT,
	"PRIMARY":                  PRIMARY,
	"FOREIGN":                  FOREIGN,
	"KEY":                      KEY,
	"REFERENCES":               REFERENCES,
	"UNIQUE":                   UNIQUE,
	"CLUSTERED":                CLUSTERED,
	"NONCLUSTERED":             NONCLUSTERED,
	"IDENTITY":                 IDENTITY,
	"ROWGUIDCOL":               ROWGUIDCOL,
	"SPARSE":                   SPARSE,
	"CASCADE":                  CASCADE,
	"RESTRICT":                 RESTRICT,
	"ACTION":                   ACTION,
	"COLLATE":                  COLLATE,
	"PERSISTED":                PERSISTED,
	"ADD":                      ADD,
	"COLUMN":                   COLUMN,
	"RENAME":                   RENAME,
	"CHECK":                    CHECK,
	"NOCHECK":                  NOCHECK,
	"DEFAULT":                  DEFAULT_KW,
	"RETURNS":                  RETURNS,
	"INCLUDE":                  INCLUDE,
	"SCHEMABINDING":            SCHEMABINDING,
	"INSTEAD":                  INSTEAD,
	"AFTER":                    AFTER,
	"OF":                       OF,
	"SELECT":                   SELECT,
	"INSERT":                   INSERT,
	"UPDATE":                   UPDATE,
	"DELETE":                   DELETE,
	"MERGE":                    MERGE,
	"USING":                    USING,
	"MATCHED":                  MATCHED,
	"TARGET":                   TARGET,
	"SOURCE":                   SOURCE,
	"INTO":                     INTO,
	"VALUES":                   VALUES,
	"VALUE":                    VALUE,
	"FROM":                     FROM,
	"WHERE":                    WHERE,
	"SET":                      SET,
	"OUTPUT":                   OUTPUT,
	"READONLY":                 READONLY,
	"JOIN":                     JOIN,
	"INNER":                    INNER,
	"LEFT":                     LEFT,
	"RIGHT":                    RIGHT,
	"FULL":                     FULL,
	"OUTER":                    OUTER,
	"CROSS":                    CROSS,
	"HASH":                     HASH,
	"LOOP":                     LOOP,
	"REMOTE":                   REMOTE,
	"APPLY":                    APPLY,
	"ON":                       ON,
	"AND":                      AND,
	"OR":                       OR,
	"NOT":                      NOT,
	"IN":                       IN,
	"EXISTS":                   EXISTS,
	"BETWEEN":                  BETWEEN,
	"LIKE":                     LIKE,
	"ESCAPE":                   ESCAPE,
	"IS":                       IS,
	"NULL":                     NULL,
	"AS":                       AS,
	"DISTINCT":                 DISTINCT,
	"ALL":                      ALL,
	"TOP":                      TOP,
	"PERCENT":                  PERCENT_KW,
	"WITH":                     WITH,
	"TIES":                     TIES,
	"ORDER":                    ORDER,
	"BY":                       BY,
	"ASC":                      ASC,
	"DESC":                     DESC,
	"GROUP":                    GROUP,
	"GROUPING":                 GROUPING,
	"CUBE":                     CUBE,
	"ROLLUP":                   ROLLUP,
	"HAVING":                   HAVING,
	"UNION":                    UNION,
	"INTERSECT":                INTERSECT,
	"EXCEPT":                   EXCEPT,
	"OFFSET":                   OFFSET,
	"FETCH":                    FETCH_KW,
	"NEXT":                     NEXT,
	"ROWS":                     ROWS,
	"ONLY":                     ONLY,
	"FIRST":                    FIRST,
	"LAST":                     LAST,
	"PRIOR":                    PRIOR,
	"ABSOLUTE":                 ABSOLUTE,
	"RELATIVE":                 RELATIVE,
	"WITHIN":                   WITHIN,
	"RANGE":                    RANGE,
	"UNBOUNDED":                UNBOUNDED,
	"PRECEDING":                PRECEDING,
	"FOLLOWING":                FOLLOWING,
	"CURRENT":                  CURRENT,
	"ROW":                      ROW,
	"PIVOT":                    PIVOT,
	"UNPIVOT":                  UNPIVOT,
	"FOR":                      FOR,
	"OPTION":                   OPTION,
	"IF":                       IF,
	"ELSE":                     ELSE,
	"BEGIN":                    BEGIN,
	"END":                      END,
	"WHILE":                    WHILE,
	"BREAK":                    BREAK,
	"CONTINUE":                 CONTINUE,
	"RETURN":                   RETURN,
	"GOTO":                     GOTO,
	"WAITFOR":                  WAITFOR,
	"DELAY":                    DELAY,
	"TIME":                     TIME,
	"TRY":                      TRY,
	"CATCH":                    CATCH,
	"THROW":                    THROW,
	"RAISERROR":                RAISERROR,
	"DECLARE":                  DECLARE,
	"CURSOR":                   CURSOR,
	"OPEN":                     OPEN,
	"CLOSE":                    CLOSE,
	"DEALLOCATE":               DEALLOCATE,
	"LOCAL":                    LOCAL,
	"GLOBAL":                   GLOBAL,
	"FORWARD_ONLY":             FORWARD_ONLY,
	"SCROLL":                   SCROLL,
	"STATIC":                   STATIC,
	"KEYSET":                   KEYSET,
	"DYNAMIC":                  DYNAMIC,
	"FAST_FORWARD":             FAST_FORWARD,
	"READ_ONLY":                READ_ONLY,
	"SCROLL_LOCKS":             SCROLL_LOCKS,
	"OPTIMISTIC":               OPTIMISTIC,
	"TYPE_WARNING":             TYPE_WARNING,
	"TRANSACTION":              TRANSACTION,
	"TRAN":                     TRAN,
	"COMMIT":                   COMMIT,
	"ROLLBACK":                 ROLLBACK,
	"SAVE":                     SAVE,
	"SAVEPOINT":                SAVEPOINT,
	"ISOLATION":                ISOLATION,
	"LEVEL":                    LEVEL,
	"SNAPSHOT":                 SNAPSHOT,
	"EXEC":                     EXEC,
	"EXECUTE":                  EXECUTE,
	"PRINT":                    PRINT,
	"USE":                      USE,
	"OVER":                     OVER,
	"PARTITION":                PARTITION,
	"ROW_NUMBER":               ROW_NUMBER,
	"RANK":                     RANK,
	"DENSE_RANK":               DENSE_RANK,
	"NTILE":                    NTILE,
	"LAG":                      LAG,
	"LEAD":                     LEAD,
	"FIRST_VALUE":              FIRST_VALUE,
	"LAST_VALUE":               LAST_VALUE,
	"CASE":                     CASE,
	"WHEN":                     WHEN,
	"THEN":                     THEN,
	"COALESCE":                 COALESCE,
	"NULLIF":                   NULLIF,
	"IIF":                      IIF,
	"CAST":                     CAST,
	"CONVERT":                  CONVERT,
	"TRY_CAST":                 TRY_CAST,
	"TRY_CONVERT":              TRY_CONVERT,
	"PARSE":                    PARSE,
	"TRY_PARSE":                TRY_PARSE,
	"TRIM":                     TRIM,
	"COUNT":                    COUNT,
	"SUM":                      SUM,
	"AVG":                      AVG,
	"MIN":                      MIN,
	"MAX":                      MAX,
	"INT":                      INT_TYPE,
	"BIGINT":                   BIGINT,
	"SMALLINT":                 SMALLINT,
	"TINYINT":                  TINYINT,
	"BIT":                      BIT,
	"DECIMAL":                  DECIMAL,
	"NUMERIC":                  NUMERIC,
	"MONEY":                    MONEY,
	"SMALLMONEY":               SMALLMONEY,
	"FLOAT":                    FLOAT_TYPE,
	"REAL":                     REAL,
	"DATE":                     DATE,
	"DATETIME":                 DATETIME,
	"DATETIME2":                DATETIME2,
	"SMALLDATETIME":            SMALLDATETIME,
	"DATETIMEOFFSET":           DATETIMEOFFSET,
	"CHAR":                     CHAR,
	"VARCHAR":                  VARCHAR,
	"TEXT":                     TEXT,
	"NCHAR":                    NCHAR,
	"NVARCHAR":                 NVARCHAR,
	"NTEXT":                    NTEXT,
	"BINARY":                   BINARY_TYPE,
	"VARBINARY":                VARBINARY,
	"IMAGE":                    IMAGE,
	"UNIQUEIDENTIFIER":         UNIQUEIDENTIFIER,
	"XML":                      XML,
	"JSON":                     JSON,
	"RAW":                      RAW,
	"AUTO":                     AUTO,
	"PATH":                     PATH,
	"EXPLICIT":                 EXPLICIT,
	"ELEMENTS":                 ELEMENTS,
	"ROOT":                     ROOT,
	"WITHOUT_ARRAY_WRAPPER":    WITHOUT_ARRAY_WRAPPER,
	"INCLUDE_NULL_VALUES":      INCLUDE_NULL_VALUES,
	"REBUILD":                  REBUILD,
	"REORGANIZE":               REORGANIZE,
	"BULK":                     BULK,
	"RECOMPILE":                RECOMPILE,
	"GENERATED":                GENERATED,
	"ALWAYS":                   ALWAYS,
	"SYSTEM_TIME":              SYSTEM_TIME,
	"PERIOD":                   PERIOD,
	"CONTAINED":                CONTAINED,
	"SYSTEM_VERSIONING":        SYSTEM_VERSIONING,
	"TO":                       TO,
	"START":                    START,
	"SQL_VARIANT":              SQL_VARIANT,
	"HIERARCHYID":              HIERARCHYID,
	"GEOMETRY":                 GEOMETRY,
	"GEOGRAPHY":                GEOGRAPHY,
	"ROWVERSION":               ROWVERSION,
	"TIMESTAMP":                TIMESTAMP,
	"GO":                       GO,
	"NOCOUNT":                  NOCOUNT,
	"OFFSETS":                  OFFSETS,
	"XACT_ABORT":               XACT_ABORT,
	"ANSI_NULLS":               ANSI_NULLS,
	"QUOTED_IDENTIFIER":        QUOTED_IDENTIFIER,
	"NOLOCK":                   NOLOCK,
	"HOLDLOCK":                 HOLDLOCK,
	"UPDLOCK":                  UPDLOCK,
	"TABLOCK":                  TABLOCK,
	"TABLOCKX":                 TABLOCKX,
	"ROWLOCK":                  ROWLOCK,
	"READPAST":                 READPAST,
	"READCOMMITTED":            READCOMMITTED,
	"READUNCOMMITTED":          READUNCOMMITTED,
	"REPEATABLEREAD":           REPEATABLEREAD,
	"SERIALIZABLE":             SERIALIZABLE,
	"TYPE":                     TYPE_WARNING,
	"ANSI_WARNINGS":            ANSI_WARNINGS,
	"ARITHABORT":               ARITHABORT,
	"ARITHIGNORE":              ARITHIGNORE,
	"ANSI_DEFAULTS":            ANSI_DEFAULTS,
	"CONCAT_NULL_YIELDS_NULL":  CONCAT_NULL_YIELDS_NULL,
	"NUMERIC_ROUNDABORT":       NUMERIC_ROUNDABORT,
	"ANSI_PADDING":             ANSI_PADDING,
	"ANSI_NULL_DFLT_ON":        ANSI_NULL_DFLT_ON,
	"CURSOR_CLOSE_ON_COMMIT":   CURSOR_CLOSE_ON_COMMIT,
	"IMPLICIT_TRANSACTIONS":    IMPLICIT_TRANSACTIONS,
	"FMTONLY":                  FMTONLY,
	"PARSEONLY":                PARSEONLY,
	"FORCEPLAN":                FORCEPLAN,
	"SHOWPLAN_TEXT":            SHOWPLAN_TEXT,
	"SHOWPLAN_ALL":             SHOWPLAN_ALL,
	"SHOWPLAN_XML":             SHOWPLAN_XML,
	"NOEXEC":                   NOEXEC,
	"REMOTE_PROC_TRANSACTIONS": REMOTE_PROC_TRANSACTIONS,
	"STATISTICS":               STATISTICS,
	"CONTEXT_INFO":             CONTEXT_INFO,
	"DEADLOCK_PRIORITY":        DEADLOCK_PRIORITY,
	"NOWAIT":                   NOWAIT,
	"HINT":                     HINT,
	"ZONE":                     ZONE,
	"TABLESAMPLE":              TABLESAMPLE,
	"ENABLE":                   ENABLE,
	"DISABLE":                  DISABLE,
	"AT":                       AT,
	"SYNONYM":                  SYNONYM,
	"REVERT":                   REVERT,
	"OPENJSON":                 OPENJSON,
	"CALLER":                   CALLER,
	"OWNER":                    OWNER_KW,
	"SELF":                     SELF,
	"USER":                     USER,
	"SEQUENCE":                 SEQUENCE,
	"INCREMENT":                INCREMENT,
	"MINVALUE":                 MINVALUE,
	"MAXVALUE":                 MAXVALUE,
	"CYCLE":                    CYCLE,
	"CACHE":                    CACHE_KW,
	"DBCC":                     DBCC,
	"GRANT":                    GRANT,
	"REVOKE":                   REVOKE,
	"DENY":                     DENY,
	"LOGIN":                    LOGIN,
	"ROLE":                     ROLE,
	"MEMBER":                   MEMBER,
	"PASSWORD":                 PASSWORD,
	"WINDOW":                   WINDOW,
	"WINDOWS":                  WINDOWS,
	"WITHOUT":                  WITHOUT,
	"AUTHORIZATION":            AUTHORIZATION,
	"BACKUP":                   BACKUP,
	"RESTORE":                  RESTORE,
	"DISK":                     DISK,
	"LOG":                      LOG,
	"COMPRESSION":              COMPRESSION,
	"INIT":                     INIT,
	"NORECOVERY":               NORECOVERY,
	"RECOVERY":                 RECOVERY,
	"FILELISTONLY":             FILELISTONLY,
	"HEADERONLY":               HEADERONLY,
	"COPY_ONLY":                COPY_ONLY,
	"CERTIFICATE":              CERTIFICATE,
	"DIFFERENTIAL":             DIFFERENTIAL,
	"STATS":                    STATS,
	"MEDIANAME":                MEDIANAME,
	"MEDIADESCRIPTION":         MEDIADESCRIPTION,
	"BLOCKSIZE":                BLOCKSIZE,
	"BUFFERCOUNT":              BUFFERCOUNT,
	"MAXTRANSFERSIZE":          MAXTRANSFERSIZE,
	"CHECKSUM":                 CHECKSUM,
	"NO_CHECKSUM":              NO_CHECKSUM,
	"CONTINUE_AFTER_ERROR":     CONTINUE_AFTER_ERROR,
	"STOP_ON_ERROR":            STOP_ON_ERROR,
	"MASTER":                   MASTER,
	"SYMMETRIC":                SYMMETRIC,
	"ASYMMETRIC":               ASYMMETRIC,
	"ENCRYPTION":               ENCRYPTION,
	"DECRYPTION":               DECRYPTION,
	"ALGORITHM":                ALGORITHM,
	"SUBJECT":                  SUBJECT,
	"ASSEMBLY":                 ASSEMBLY,
	"PERMISSION_SET":           PERMISSION_SET,
	"SAFE":                     SAFE,
	"EXTERNAL_ACCESS":          EXTERNAL_ACCESS,
	"UNSAFE":                   UNSAFE,
	"SCHEME":                   SCHEME,
	"SPLIT":                    SPLIT,
	"USED":                     USED,
	"CONTAINS":                 CONTAINS,
	"FREETEXT":                 FREETEXT,
	"CONTAINSTABLE":            CONTAINSTABLE,
	"FREETEXTTABLE":            FREETEXTTABLE,
	"FULLTEXT":                 FULLTEXT,
	"CATALOG":                  CATALOG,
	"LANGUAGE":                 LANGUAGE,
	"STOPLIST":                 STOPLIST,
	"RESOURCE":                 RESOURCE,
	"POOL":                     POOL,
	"WORKLOAD":                 WORKLOAD,
	"GOVERNOR":                 GOVERNOR,
	"CLASSIFIER":               CLASSIFIER,
	"RECONFIGURE":              RECONFIGURE,
	"AVAILABILITY":             AVAILABILITY,
	"REPLICA":                  REPLICA,
	"ENDPOINT_URL":             ENDPOINT_URL,
	"FAILOVER":                 FAILOVER,
	"SYNCHRONOUS_COMMIT":       SYNCHRONOUS_COMMIT,
	"ASYNCHRONOUS_COMMIT":      ASYNCHRONOUS_COMMIT,
	"PRIMARY_ROLE":             PRIMARY_ROLE,
	"SECONDARY_ROLE":           SECONDARY_ROLE,
	"LISTENER":                 LISTENER,
	"MESSAGE":                  MESSAGE,
	"CONTRACT":                 CONTRACT,
	"QUEUE":                    QUEUE,
	"SERVICE":                  SERVICE,
	"DIALOG":                   DIALOG,
	"CONVERSATION":             CONVERSATION,
	"VALIDATION":               VALIDATION,
	"WELL_FORMED_XML":          WELL_FORMED_XML,
	"EMPTY":                    EMPTY,
	"INITIATOR":                INITIATOR,
	"SENT":                     SENT,
	"ACTIVATION":               ACTIVATION,
	"RETENTION":                RETENTION,
	"POISON_MESSAGE_HANDLING":  POISON_MESSAGE_HANDLING,
	"RECEIVE":                  RECEIVE,
	"SEND":                     SEND,
	"MOVE":                     MOVE,
	"GET":                      GET,
	"RESULT":                   RESULT,
	"UNDEFINED":                UNDEFINED,
	"NONE":                     NONE_KW,
	"SETS":                     SETS,
}

// String returns a string representation of the token type.
func (t Type) String() string {
	if name, ok := tokenNames[t]; ok {
		return name
	}
	// Check keywords
	for kw, typ := range keywords {
		if typ == t {
			return kw
		}
	}
	return "UNKNOWN"
}

// LookupIdent checks if an identifier is a keyword.
func LookupIdent(ident string) Type {
	if tok, ok := keywords[ident]; ok {
		return tok
	}
	return IDENT
}

// IsKeyword returns true if the token type is a keyword.
func (t Type) IsKeyword() bool {
	return t > keyword_beg && t < keyword_end
}

// Token represents a lexical token with position information.
type Token struct {
	Type    Type
	Literal string
	Line    int
	Column  int
}

// Position represents a position in source code.
type Position struct {
	Line   int
	Column int
	Offset int
}
