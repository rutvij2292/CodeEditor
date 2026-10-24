<?php

/**
 * A stream bucket is a chunk of a stream which can be extracted from bucket brigades.
 * @since 8.4
 */
final class StreamBucket
{
    public $bucket;

    public string $data;

    public int $datalen;

    public int $dataLength;
}
