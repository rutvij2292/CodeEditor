<?php

/**
 * Children of this class are passed to stream_filter_register. Note that the __construct method is
 * not called; instead, php_user_filter::onCreate should be used for initialization.
 */
class php_user_filter
{
    public string $filtername;

    public mixed $params;

    public $stream;

    /**
     * Called when applying the filter
     *
     * This method is called whenever data is read from or written to the attached stream (such as
     * with fread or fwrite).
     * @param resource $in  is a resource pointing to a bucket brigade</i< which contains one or more bucket objects containing data to be filtered.
     * @param resource $out is a resource pointing to a second bucket brigade into which your modified buckets should be placed.
     * @param int &$consumed which must always be declared by reference, should be incremented by the length of the data which your filter reads in and alters. In most cases this means you will increment consumed by $bucket->datalen for each $bucket.
     * @param bool $closing If the stream is in the process of closing (and therefore this is the last pass through the filterchain), the closing parameter will be set to TRUE
     * @return int The filter() method must return one of three values upon completion. Return Value Meaning PSFS_PASS_ON Filter processed successfully with data available in the out bucket brigade. PSFS_FEED_ME Filter processed successfully, however no data was available to return. More data is required ...
     */
    public function filter(
        $in,
        $out,
        &$consumed,
        bool $closing
    ): int {}

    /**
     * Called when creating the filter
     *
     * This method is called during instantiation of the filter class object. If your filter
     * allocates or initializes any other resources (such as a buffer), this is the place to do it.
     * @return bool Your implementation of this method should return false on failure, or true on success.
     */
    public function onCreate(): bool {}

    /**
     * Called when closing the filter
     *
     * This method is called upon filter shutdown (typically, this is also during stream shutdown),
     * and is executed after the flush method is called. If any resources were allocated or
     * initialized during onCreate() this would be the time to destroy or dispose of them.
     */
    public function onClose(): void {}

    /**
     * @param int $offset
     * @param int $whence
     * @param int $chain
     * @return bool
     * @since 8.6
     */
    public function seek(int $offset, int $whence, int $chain): bool {}
}
