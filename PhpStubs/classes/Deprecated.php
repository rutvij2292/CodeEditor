<?php

/**
 * This attribute is used to mark functionality as deprecated. Using deprecated functionality will
 * cause an E_USER_DEPRECATED error to be emitted.
 * @since 8.4
 */
final class Deprecated
{
    public readonly ?string $message;

    public readonly ?string $since;

    /**
     * Construct a new Deprecated attribute instance
     *
     * Constructs a new Deprecated instance.
     * @param string|null $message The value of the message property.
     * @param string|null $since The value of the since property.
     */
    public function __construct(?string $message = null, ?string $since = null) {}
}
