<?php

class JsonIncrementalParser
{
    public const JSON_PARSER_SUCCESS = 0;

    public const JSON_PARSER_CONTINUE = 1;

    /**
     * @param int $depth [optional]
     * @param int $options [optional]
     */
    public function __construct($depth, $options) {}

    public function getError() {}

    public function reset() {}

    /**
     * @param string $json
     */
    public function parse($json) {}

    /**
     * @param string $filename
     */
    public function parseFile($filename) {}

    /**
     * @param int $options [optional]
     */
    public function get($options) {}
}
