<?php

/**
 * SessionUpdateTimestampHandlerInterface is an interface which
 * defines a prototype for updating the life time of an existing session.
 * In order to use the lazy_write option must be enabled and a custom session
 * handler must implement this interface.
 * @since 7.0
 */
interface SessionUpdateTimestampHandlerInterface
{
    /**
     * Validate session id
     * @param string $id The session id
     * @return bool Note this value is returned internally to PHP for processing.
     */
    public function validateId(string $id): bool;

    /**
     * Update timestamp of a session
     * @param string $id The session id
     * @param string $data The encoded session data. This data is the result of the PHP internally encoding the $_SESSION superglobal to a serialized string and passing it as this parameter. Please note sessions use an alternative serialization method.
     * @return bool Returns true if the timestamp was updated, false otherwise. Note that this value is returned internally to PHP for processing.
     */
    public function updateTimestamp(string $id, string $data): bool;
}
