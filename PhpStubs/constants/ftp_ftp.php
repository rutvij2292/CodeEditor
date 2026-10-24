<?php

const FTP_ASCII = 1;

const FTP_TEXT = 1;

const FTP_BINARY = 2;

const FTP_IMAGE = 2;

/**
 * Automatically determine resume position and start position for GET and PUT requests
 * (only works if FTP_AUTOSEEK is enabled)
 */
const FTP_AUTORESUME = -1;

/**
 * See ftp_set_option for information.
 */
const FTP_TIMEOUT_SEC = 0;

/**
 * See ftp_set_option for information.
 */
const FTP_AUTOSEEK = 1;

const FTP_USEPASVADDRESS = 2;

/**
 * Asynchronous transfer has failed
 */
const FTP_FAILED = 0;

/**
 * Asynchronous transfer has finished
 */
const FTP_FINISHED = 1;

/**
 * Asynchronous transfer is still active
 */
const FTP_MOREDATA = 2;
