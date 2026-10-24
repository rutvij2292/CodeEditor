<?php
namespace Dom;

/**
 * Represents an XML document.
 * @since 8.4
 */
final class XMLDocument extends Document
{
    public static function createEmpty(string $version = "1.0", string $encoding = "UTF-8"): XMLDocument {}

    public static function createFromFile(string $path, int $options = 0, ?string $overrideEncoding = null): XMLDocument {}

    public static function createFromString(string $source, int $options = 0, ?string $overrideEncoding = null): XMLDocument {}

    public string $xmlEncoding;

    public bool $xmlStandalone;

    public string $xmlVersion;

    public bool $formatOutput;

    public function createEntityReference(string $name): EntityReference {}

    public function validate(): bool {}

    public function xinclude(int $options = 0): int {}

    public function saveXml(?Node $node = null, int $options = 0): string|false {}

    public function saveXmlFile(string $filename, int $options = 0): int|false {}
}
