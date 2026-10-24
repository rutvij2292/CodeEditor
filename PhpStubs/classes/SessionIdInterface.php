<?php

/**
 * SessionIdInterface
 * @since 5.5
 */
interface SessionIdInterface
{
    /**
     * Create session ID
     * @return string The new session ID. Note that this value is returned internally to PHP for processing.
     */
    public function create_sid(): string;
}
