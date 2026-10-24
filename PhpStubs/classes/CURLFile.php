<?php

/**
 * This class or CURLStringFile should be used to upload a file with CURLOPT_POSTFIELDS.
 *
 * Unserialization of CURLFile instances is not allowed. As of PHP 7.4.0, serialization is forbidden
 * in the first place.
 */
class CURLFile
{
    public string $name;

    public string $mime;

    public string $postname;

    /**
     * Create a CURLFile object
     * @param string $filename Path to the file which will be uploaded.
     * @param string $mime_type [optional] Mimetype of the file.
     * @param string $posted_filename [optional] Name of the file.
     * @since 5.5
     */
    public function __construct(
        string $filename,
        string|null $mime_type = null,
        string|null $posted_filename = null
    ) {}

    /**
     * Get file name
     * @return string Returns file name.
     * @since 5.5
     */
    public function getFilename(): string {}

    /**
     * Get MIME type
     * @return string Returns MIME type.
     * @since 5.5
     */
    public function getMimeType(): string {}

    /**
     * Get file name for POST
     * @return string Returns file name for POST.
     * @since 5.5
     */
    public function getPostFilename(): string {}

    /**
     * Set MIME type
     * @param string $mime_type MIME type to be used in POST data.
     * @since 5.5
     */
    public function setMimeType(string $mime_type): void {}

    /**
     * Set file name for POST
     * https://secure.php.net/manual/en/curlfile.setpostfilename.php
     * @param string $posted_filename Filename to be used in POST data.
     * @since 5.5
     */
    public function setPostFilename(string $posted_filename): void {}

    /**
     * Unserialization handler
     * @since 5.5
     */
    public function __wakeup() {}
}
