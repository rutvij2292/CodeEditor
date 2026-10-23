import Foundation

/// Class, interface, trait and enum names declared by PHP 8.3 and its common extensions (from get_declared_classes()).
/// Used only to avoid reporting built-in classes as undefined.
enum NPDiagBuiltins {
    private static let raw = """
    __PHP_Incomplete_Class AddressInfo AllowDynamicProperties AppendIterator ArgumentCountError ArithmeticError
    ArrayAccess ArrayIterator ArrayObject AssertionError Attribute BackedEnum BadFunctionCallException
    BadMethodCallException CachingIterator CallbackFilterIterator ClosedGeneratorException Closure Collator
    CompileError Countable CURLFile CurlHandle CurlMultiHandle CurlShareHandle CURLStringFile DateError
    DateException DateInterval DateInvalidOperationException DateInvalidTimeZoneException
    DateMalformedIntervalStringException DateMalformedPeriodStringException DateMalformedStringException
    DateObjectError DatePeriod DateRangeError DateTime DateTimeImmutable DateTimeInterface DateTimeZone
    DeflateContext Directory DirectoryIterator DivisionByZeroError DomainException DOMAttr DOMCdataSection
    DOMCharacterData DOMChildNode DOMComment DOMDocument DOMDocumentFragment DOMDocumentType DOMElement DOMEntity
    DOMEntityReference DOMException DOMImplementation DOMNamedNodeMap DOMNameSpaceNode DOMNode DOMNodeList
    DOMNotation DOMParentNode DOMProcessingInstruction DOMText DOMXPath EmptyIterator Error ErrorException
    Exception FFI FFI\\CData FFI\\CType FFI\\Exception FFI\\ParserException Fiber FiberError FilesystemIterator
    FilterIterator finfo FTP\\Connection GdFont GdImage Generator GlobIterator GMP HashContext Imagick ImagickDraw
    ImagickDrawException ImagickException ImagickKernel ImagickKernelException ImagickPixel ImagickPixelException
    ImagickPixelIterator ImagickPixelIteratorException IMAP\\Connection InfiniteIterator InflateContext
    InternalIterator IntlBreakIterator IntlCalendar IntlChar IntlCodePointBreakIterator IntlDateFormatter
    IntlDatePatternGenerator IntlException IntlGregorianCalendar IntlIterator IntlPartsIterator
    IntlRuleBasedBreakIterator IntlTimeZone InvalidArgumentException Iterator IteratorAggregate IteratorIterator
    JsonException JsonSerializable LDAP\\Connection LDAP\\Result LDAP\\ResultEntry LengthException LibXMLError
    LimitIterator Locale LogicException MessageFormatter MultipleIterator mysqli
    mysqli_driver mysqli_result mysqli_sql_exception mysqli_stmt mysqli_warning NoRewindIterator Normalizer
    NumberFormatter OpenSSLAsymmetricKey OpenSSLCertificate OpenSSLCertificateSigningRequest OuterIterator
    OutOfBoundsException OutOfRangeException OverflowException Override ParentIterator ParseError PDO
    PDOException PDORow PDOStatement PgSql\\Connection PgSql\\Lob PgSql\\Result Phar PharData PharException
    PharFileInfo php_user_filter PhpToken RangeException
    RecursiveArrayIterator RecursiveCachingIterator RecursiveCallbackFilterIterator RecursiveDirectoryIterator
    RecursiveFilterIterator RecursiveIterator RecursiveIteratorIterator RecursiveRegexIterator
    RecursiveTreeIterator Redis RedisArray RedisCluster RedisClusterException RedisException RedisSentinel
    Reflection ReflectionAttribute ReflectionClass ReflectionClassConstant ReflectionEnum
    ReflectionEnumBackedCase ReflectionEnumUnitCase ReflectionException ReflectionExtension ReflectionFiber
    ReflectionFunction ReflectionFunctionAbstract ReflectionGenerator ReflectionIntersectionType ReflectionMethod
    ReflectionNamedType ReflectionObject ReflectionParameter ReflectionProperty ReflectionReference
    ReflectionType ReflectionUnionType ReflectionZendExtension Reflector RegexIterator ResourceBundle
    ReturnTypeWillChange RuntimeException SeekableIterator SensitiveParameter SensitiveParameterValue
    Serializable SessionHandler SessionHandlerInterface SessionIdInterface SessionUpdateTimestampHandlerInterface
    Shmop SimpleXMLElement SimpleXMLIterator SoapClient SoapFault SoapHeader SoapParam SoapServer SoapVar Socket
    SodiumException SplDoublyLinkedList SplFileInfo SplFileObject SplFixedArray SplHeap SplMaxHeap SplMinHeap
    SplObjectStorage SplObserver SplPriorityQueue SplQueue SplStack SplSubject SplTempFileObject Spoofchecker
    SQLite3 SQLite3Exception SQLite3Result SQLite3Stmt stdClass Stringable SysvMessageQueue SysvSemaphore
    SysvSharedMemory Throwable Transliterator Traversable TypeError UConverter UnderflowException
    UnexpectedValueException UnhandledMatchError UnitEnum ValueError WeakMap WeakReference XMLParser XMLReader
    XMLWriter XSLTProcessor ZipArchive COM DOTNET VARIANT Deprecated NoDiscard Memcached MemcachedException
    """

    static let names: Set<String> = Set(raw.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { $0.lowercased() })

    /// Namespaces of core / extension classes (MongoDB driver, Random, Dom, Pdo ...) that this table cannot enumerate fully.
    static let namespacePrefixes = ["random\\", "dom\\", "pdo\\", "intl\\", "uri\\", "mongodb\\", "ffi\\", "zstd\\", "ds\\", "swoole\\", "openswoole\\"]

    static func contains(_ fqn: String) -> Bool {
        let l = fqn.lowercased()
        if names.contains(l) { return true }
        return namespacePrefixes.contains { l.hasPrefix($0) }
    }
}
