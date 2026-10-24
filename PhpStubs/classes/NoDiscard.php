<?php

/**
 * This attribute can be used to indicate that the return value of a function or a method should not
 * be discarded. If the return value is not used in any way, a warning will be emitted.
 *
 * This is useful for functions where not checking the return value is likely to be a bug. To
 * intentionally discard the return value of such a function, use (void) cast to suppress the
 * warning.
 * @since 8.5
 */
final class NoDiscard
{
    public readonly ?string $message;

    /**
     * Construct a new NoDiscard attribute instance
     *
     * Constructs a new NoDiscard instance.
     * @param string|null $message The value of the message property.
     */
    public function __construct(?string $message = null) {}
}
