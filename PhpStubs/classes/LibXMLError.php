<?php

/**
 * Contains various information about errors thrown by libxml. The error codes
 * are described within the official
 * xmlError API documentation.
 */
class LibXMLError
{
    /**
     * the severity of the error (one of the following constants:
     * LIBXML_ERR_WARNING,
     * LIBXML_ERR_ERROR or
     * LIBXML_ERR_FATAL)
     * @var int
     */
    public int $level;

    /**
     * The error's code.
     * @var int
     */
    public int $code;

    /**
     * The column where the error occurred.
     *
     * Note:
     *
     * This property isn't entirely implemented in libxml and therefore
     * 0 is often returned.
     * @var int
     */
    public int $column;

    /**
     * The error message, if any.
     * @var string
     */
    public string $message;

    /**
     * The filename, or empty if the XML was loaded from a string.
     * @var string
     */
    public string $file;

    /**
     * The line where the error occurred.
     * @var int
     */
    public int $line;
}
