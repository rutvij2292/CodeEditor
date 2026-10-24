<?php

/**
 * SessionHandlerInterface is an interface which defines
 * a prototype for creating a custom session handler.
 * In order to pass a custom session handler to
 * session_set_save_handler() using its OOP invocation,
 * the class must implement this interface.
 * @since 5.4
 */
interface SessionHandlerInterface
{
    /**
     * Close the session
     * @return bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function close(): bool;

    /**
     * Destroy a session
     * @param string $id The session ID being destroyed.
     * @return bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function destroy(string $id): bool;

    /**
     * Cleanup old sessions
     * @param int $max_lifetime Sessions that have not updated for the last maxlifetime seconds will be removed.
     * @return int|false Returns the number of deleted sessions on success, or false on failure. Prior to PHP version 7.1, the function returned true on success. Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function gc(int $max_lifetime): int|false;

    /**
     * Initialize session
     * @param string $path The path where to store/retrieve the session.
     * @param string $name The session name.
     * @return bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function open(
        string $path,
        string $name
    ): bool;

    /**
     * Read session data
     * @param string $id The session id to read data for.
     * @return string|false Returns an encoded string of the read data. If nothing was read, it must return false. Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function read(string $id): string|false;

    /**
     * Write session data
     * @param string $id The session id.
     * @param string $data The encoded session data. This data is the result of the PHP internally encoding the $_SESSION superglobal to a serialized string and passing it as this parameter. Please note sessions use an alternative serialization method.
     * @return bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function write(
        string $id,
        string $data
    ): bool;
}
