<?php

/**
 * @since 8.6
 */
final class StreamPollHandle implements \Io\Poll\Handle
{
    public function __construct($stream) {}

    public function getStream() {}

    public function isValid(): bool {}
}
