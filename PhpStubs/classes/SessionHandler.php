<?php

/**
 * SessionHandler a special class that can
 * be used to expose the current internal PHP session
 * save handler by inheritance. There are six methods
 * which wrap the six internal session save handler
 * callbacks (open, close, read, write, destroy and gc).
 * By default, this class will wrap whatever internal
 * save handler is set as as defined by the
 * session.save_handler configuration directive which is usually
 * files by default. Other internal session save handlers are provided by
 * PHP extensions such as SQLite (as sqlite),
 * Memcache (as memcache), and Memcached (as memcached).
 * @since 5.4
 */
class SessionHandler implements SessionHandlerInterface, SessionIdInterface
{
    /**
     * Close the session
     * @return bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function close(): bool {}

    /**
     * Return a new session ID
     * @return string A session ID valid for the default session handler.
     * @since 5.5
     */
    public function create_sid(): string {}

    /**
     * Destroy a session
     * @param string $id The session ID being destroyed.
     * @return bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function destroy(string $id): bool {}

    /**
     * Cleanup old sessions
     * @param int $max_lifetime Sessions that have not updated for the last maxlifetime seconds will be removed.
     * @return int|bool The return value (usually TRUE on success, FALSE on failure). Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function gc(int $max_lifetime): int|false {}

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
    ): bool {}

    /**
     * Read session data
     * @param string $id The session id to read data for.
     * @return string|false Returns an encoded string of the read data. If nothing was read, it must return an empty string. Note this value is returned internally to PHP for processing.
     * @since 5.4
     */
    public function read(string $id): string|false {}

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
    ): bool {}

    /**
     * Validate session id
     * @param string $id The session id
     * @return bool Returns true if the session id is valid, false otherwise.
     * @since 8.6
     */
    public function validateId(string $id): bool {}
}
