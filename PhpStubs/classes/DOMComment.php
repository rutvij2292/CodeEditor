<?php

/**
 * The DOMComment class represents comment nodes,
 * characters delimited by lt;!-- and -->.
 */
class DOMComment extends DOMCharacterData
{
    /**
     * Creates a new DOMComment object
     * @param string $data [optional] The value of the comment
     */
    public function __construct(string $data = '') {}
}
