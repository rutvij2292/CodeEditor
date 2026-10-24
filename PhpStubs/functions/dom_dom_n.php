<?php

/**
 * Gets a Dom\Attr or Dom\Element object from a SimpleXMLElement object
 *
 * This function takes the given attribute or element node (a SimpleXMLElement instance) and creates
 * a Dom\Attr or Dom\Element node, respectively. The new Dom\Node refers to the same underlying XML
 * node as the SimpleXMLElement.
 * @since 8.4
 */
function import_simplexml(object $node): Attr|Element {}
