<?php

/**
 * Clears the accumulated stream errors
 * @return void
 * @since 8.6
 */
function stream_clear_errors(): void {}

/**
 * Returns the accumulated stream errors
 * @return StreamError[]
 * @since 8.6
 */
function stream_last_errors(): array {}

/**
 * Returns the current crypto status of a stream
 * @param resource $stream
 * @return int
 * @since 8.6
 */
function stream_socket_get_crypto_status($stream): int {}
