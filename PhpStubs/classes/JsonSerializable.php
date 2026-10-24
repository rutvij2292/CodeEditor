<?php

/**
 * Objects implementing JsonSerializable
 * can customize their JSON representation when encoded with
 * json_encode.
 * @since 5.4
 */
interface JsonSerializable
{
    /**
     * Specify data which should be serialized to JSON
     * @return mixed data which can be serialized by json_encode, which is a value of any type other than a resource.
     * @since 5.4
     */
    public function jsonSerialize(): mixed;
}
