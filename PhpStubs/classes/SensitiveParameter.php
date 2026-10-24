<?php

/**
 * This attribute is used to mark a parameter that is sensitive and should have its value redacted
 * if present in a stack trace.
 * @since 8.2
 */
final class SensitiveParameter
{
    /**
     * Construct a new SensitiveParameter attribute instance
     *
     * Constructs a new SensitiveParameter instance.
     */
    public function __construct() {}
}
