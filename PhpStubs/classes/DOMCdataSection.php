<?php

/**
 * The DOMCdataSection inherits from DOMText for textural representation of CData constructs.
 */
class DOMCdataSection extends DOMText
{
    /**
     * Constructs a new DOMCdataSection object
     * @param string $data The value of the CDATA node. If not supplied, an empty CDATA node is created.
     */
    public function __construct(string $data) {}
}
