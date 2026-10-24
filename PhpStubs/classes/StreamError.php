<?php

/**
 * @since 8.6
 */
final readonly class StreamError
{
    public readonly StreamErrorCode $code;

    public readonly string $message;

    public readonly string $wrapperName;

    public readonly int $severity;

    public readonly bool $terminating;

    public readonly ?string $param;
}
