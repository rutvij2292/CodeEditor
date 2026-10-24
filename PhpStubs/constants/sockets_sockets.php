<?php

const AF_UNIX = 1;

const AF_INET = 2;

/**
 * Only available if compiled with IPv6 support.
 */
const AF_INET6 = 10;

const SOCK_STREAM = 1;

const SOCK_DGRAM = 2;

const SOCK_RAW = 3;

const SOCK_SEQPACKET = 5;

const SOCK_RDM = 4;

const MSG_OOB = 1;

const MSG_WAITALL = 256;

const MSG_CTRUNC = 8;

const MSG_TRUNC = 32;

const MSG_PEEK = 2;

const MSG_DONTROUTE = 4;

/**
 * Not available on Windows platforms.
 */
const MSG_EOR = 128;

/**
 * Not available on Windows platforms.
 */
const MSG_EOF = 512;

const MSG_CONFIRM = 2048;

const MSG_ERRQUEUE = 8192;

const MSG_NOSIGNAL = 16384;

const MSG_DONTWAIT = 64;

const MSG_MORE = 32768;

const MSG_WAITFORONE = 65536;

const MSG_CMSG_CLOEXEC = 1073741824;

const SO_DEBUG = 1;

const SO_REUSEADDR = 2;

/**
 * This constant is only available in PHP 5.4.10 or later on platforms that
 * support the SO_REUSEPORT socket option: this
 * includes Mac OS X and FreeBSD, but does not include Linux or Windows.
 */
const SO_REUSEPORT = 15;

const SO_KEEPALIVE = 9;

const SO_DONTROUTE = 5;

const SO_LINGER = 13;

const SO_BROADCAST = 6;

const SO_OOBINLINE = 10;

const SO_SNDBUF = 7;

const SO_RCVBUF = 8;

const SO_SNDLOWAT = 19;

const SO_RCVLOWAT = 18;

const SO_SNDTIMEO = 21;

const SO_RCVTIMEO = 20;

const SO_TYPE = 3;

const SO_ERROR = 4;

const SO_BINDTODEVICE = 25;

const SO_ATTACH_REUSEPORT_CBPF = 51;

const SO_DETACH_FILTER = 27;

const SO_DETACH_BPF = 27;

/**
 * @since 8.6
 */
const SO_DETACH_REUSEPORT_BPF = 68;

const SOL_SOCKET = 1;

const SOL_UDPLITE = 136;

const SOMAXCONN = 128;

/**
 * @since 8.1
 */
const SO_MARK = 36;

/**
 * Used to disable Nagle TCP algorithm.
 * Added in PHP 5.2.7.
 */
const TCP_NODELAY = 1;

const PHP_NORMAL_READ = 1;

const PHP_BINARY_READ = 2;

/**
 * Joins a multicast group.
 * @since 5.4
 */
const MCAST_JOIN_GROUP = 42;

/**
 * Leaves a multicast group.
 * @since 5.4
 */
const MCAST_LEAVE_GROUP = 45;

/**
 * Blocks packets arriving from a specific source to a specific multicast group,
 * which must have been previously joined.
 * @since 5.4
 */
const MCAST_BLOCK_SOURCE = 43;

/**
 * Unblocks (start receiving again) packets arriving from
 * a specific source address to a specific multicast group,
 * which must have been previously joined.
 * @since 5.4
 */
const MCAST_UNBLOCK_SOURCE = 44;

/**
 * Receive packets destined to a specific multicast group
 * whose source address matches a specific value.
 * @since 5.4
 */
const MCAST_JOIN_SOURCE_GROUP = 46;

/**
 * Stop receiving packets destined to a specific multicast group
 * whose soure address matches a specific value.
 * @since 5.4
 */
const MCAST_LEAVE_SOURCE_GROUP = 47;

/**
 * The outgoing interface for IPv4 multicast packets.
 * @since 5.4
 */
const IP_MULTICAST_IF = 32;

/**
 * The outgoing interface for IPv6 multicast packets.
 * @since 5.4
 */
const IP_MULTICAST_TTL = 33;

/**
 * The multicast loopback policy for IPv4 packets,
 * which determines whether multicast packets sent by this socket
 * also reach receivers in the same host that have joined the same multicast group
 * on the outgoing interface used by this socket. This is the case by default.
 * @since 5.4
 */
const IP_MULTICAST_LOOP = 34;

/**
 * Analogous to IP_MULTICAST_LOOP, but for IPv6.
 * @since 5.4
 */
const IPV6_MULTICAST_IF = 17;

/**
 * The time-to-live of outgoing IPv4 multicast packets.
 * This should be a value between 0 (don't leave the interface) and 255.
 * The default value is 1 (only the local network is reached).
 * @since 5.4
 */
const IPV6_MULTICAST_HOPS = 18;

/**
 * Analogous to IP_MULTICAST_TTL, but for IPv6 packets.
 * The value -1 is also accepted, meaning the route default should be used.
 * @since 5.4
 */
const IPV6_MULTICAST_LOOP = 19;

const IPV6_V6ONLY = 26;

const IP_BIND_ADDRESS_NO_PORT = 24;

const IP_MTU_DISCOVER = 10;

const IP_PMTUDISC_DO = 2;

const IP_PMTUDISC_DONT = 0;

const IP_PMTUDISC_WANT = 1;

const IP_PMTUDISC_PROBE = 3;

const IP_PMTUDISC_INTERFACE = 4;

const IP_PMTUDISC_OMIT = 5;

/**
 * Operation not permitted.
 */
const SOCKET_EPERM = 1;

/**
 * No such file or directory.
 */
const SOCKET_ENOENT = 2;

/**
 * Interrupted system call.
 */
const SOCKET_EINTR = 4;

/**
 * I/O error.
 */
const SOCKET_EIO = 5;

/**
 * No such device or address.
 */
const SOCKET_ENXIO = 6;

/**
 * Arg list too long.
 */
const SOCKET_E2BIG = 7;

/**
 * Bad file number.
 */
const SOCKET_EBADF = 9;

/**
 * Try again.
 */
const SOCKET_EAGAIN = 11;

/**
 * Out of memory.
 */
const SOCKET_ENOMEM = 12;

/**
 * Permission denied.
 */
const SOCKET_EACCES = 13;

/**
 * Bad address.
 */
const SOCKET_EFAULT = 14;

/**
 * Block device required.
 */
const SOCKET_ENOTBLK = 15;

/**
 * Device or resource busy.
 */
const SOCKET_EBUSY = 16;

/**
 * File exists.
 */
const SOCKET_EEXIST = 17;

/**
 * Cross-device link.
 */
const SOCKET_EXDEV = 18;

/**
 * No such device.
 */
const SOCKET_ENODEV = 19;

/**
 * Not a directory.
 */
const SOCKET_ENOTDIR = 20;

/**
 * Is a directory.
 */
const SOCKET_EISDIR = 21;

/**
 * Invalid argument.
 */
const SOCKET_EINVAL = 22;

/**
 * File table overflow.
 */
const SOCKET_ENFILE = 23;

/**
 * Too many open files.
 */
const SOCKET_EMFILE = 24;

/**
 * Not a typewriter.
 */
const SOCKET_ENOTTY = 25;

/**
 * No space left on device.
 */
const SOCKET_ENOSPC = 28;

/**
 * Illegal seek.
 */
const SOCKET_ESPIPE = 29;

/**
 * Read-only file system.
 */
const SOCKET_EROFS = 30;

/**
 * Too many links.
 */
const SOCKET_EMLINK = 31;

/**
 * Broken pipe.
 */
const SOCKET_EPIPE = 32;

/**
 * File name too long.
 */
const SOCKET_ENAMETOOLONG = 36;

/**
 * No record locks available.
 */
const SOCKET_ENOLCK = 37;

/**
 * Function not implemented.
 */
const SOCKET_ENOSYS = 38;

/**
 * Directory not empty.
 */
const SOCKET_ENOTEMPTY = 39;

/**
 * Too many symbolic links encountered.
 */
const SOCKET_ELOOP = 40;

/**
 * Operation would block.
 */
const SOCKET_EWOULDBLOCK = 11;

/**
 * No message of desired type.
 */
const SOCKET_ENOMSG = 42;

/**
 * Identifier removed.
 */
const SOCKET_EIDRM = 43;

/**
 * Channel number out of range.
 */
const SOCKET_ECHRNG = 44;

/**
 * Level 2 not synchronized.
 */
const SOCKET_EL2NSYNC = 45;

/**
 * Level 3 halted.
 */
const SOCKET_EL3HLT = 46;

/**
 * Level 3 reset.
 */
const SOCKET_EL3RST = 47;

/**
 * Link number out of range.
 */
const SOCKET_ELNRNG = 48;

/**
 * Protocol driver not attached.
 */
const SOCKET_EUNATCH = 49;

/**
 * No CSI structure available.
 */
const SOCKET_ENOCSI = 50;

/**
 * Level 2 halted.
 */
const SOCKET_EL2HLT = 51;

/**
 * Invalid exchange.
 */
const SOCKET_EBADE = 52;

/**
 * Invalid request descriptor.
 */
const SOCKET_EBADR = 53;

/**
 * Exchange full.
 */
const SOCKET_EXFULL = 54;

/**
 * No anode.
 */
const SOCKET_ENOANO = 55;

/**
 * Invalid request code.
 */
const SOCKET_EBADRQC = 56;

/**
 * Invalid slot.
 */
const SOCKET_EBADSLT = 57;

/**
 * Device not a stream.
 */
const SOCKET_ENOSTR = 60;

/**
 * No data available.
 */
const SOCKET_ENODATA = 61;

/**
 * Timer expired.
 */
const SOCKET_ETIME = 62;

/**
 * Out of streams resources.
 */
const SOCKET_ENOSR = 63;

/**
 * Machine is not on the network.
 */
const SOCKET_ENONET = 64;

/**
 * Object is remote.
 */
const SOCKET_EREMOTE = 66;

/**
 * Link has been severed.
 */
const SOCKET_ENOLINK = 67;

/**
 * Advertise error.
 */
const SOCKET_EADV = 68;

/**
 * Srmount error.
 */
const SOCKET_ESRMNT = 69;

/**
 * Communication error on send.
 */
const SOCKET_ECOMM = 70;

/**
 * Protocol error.
 */
const SOCKET_EPROTO = 71;

/**
 * Multihop attempted.
 */
const SOCKET_EMULTIHOP = 72;

/**
 * Not a data message.
 */
const SOCKET_EBADMSG = 74;

/**
 * Name not unique on network.
 */
const SOCKET_ENOTUNIQ = 76;

/**
 * File descriptor in bad state.
 */
const SOCKET_EBADFD = 77;

/**
 * Remote address changed.
 */
const SOCKET_EREMCHG = 78;

/**
 * Interrupted system call should be restarted.
 */
const SOCKET_ERESTART = 85;

/**
 * Streams pipe error.
 */
const SOCKET_ESTRPIPE = 86;

/**
 * Too many users.
 */
const SOCKET_EUSERS = 87;

/**
 * Socket operation on non-socket.
 */
const SOCKET_ENOTSOCK = 88;

/**
 * Destination address required.
 */
const SOCKET_EDESTADDRREQ = 89;

/**
 * Message too long.
 */
const SOCKET_EMSGSIZE = 90;

/**
 * Protocol wrong type for socket.
 */
const SOCKET_EPROTOTYPE = 91;

const SOCKET_ENOPROTOOPT = 92;

/**
 * Protocol not supported.
 */
const SOCKET_EPROTONOSUPPORT = 93;

/**
 * Socket type not supported.
 */
const SOCKET_ESOCKTNOSUPPORT = 94;

/**
 * Operation not supported on transport endpoint.
 */
const SOCKET_EOPNOTSUPP = 95;

/**
 * Protocol family not supported.
 */
const SOCKET_EPFNOSUPPORT = 96;

/**
 * Address family not supported by protocol.
 */
const SOCKET_EAFNOSUPPORT = 97;

const SOCKET_EADDRINUSE = 98;

/**
 * Cannot assign requested address.
 */
const SOCKET_EADDRNOTAVAIL = 99;

/**
 * Network is down.
 */
const SOCKET_ENETDOWN = 100;

/**
 * Network is unreachable.
 */
const SOCKET_ENETUNREACH = 101;

/**
 * Network dropped connection because of reset.
 */
const SOCKET_ENETRESET = 102;

/**
 * Software caused connection abort.
 */
const SOCKET_ECONNABORTED = 103;

/**
 * Connection reset by peer.
 */
const SOCKET_ECONNRESET = 104;

/**
 * No buffer space available.
 */
const SOCKET_ENOBUFS = 105;

/**
 * Transport endpoint is already connected.
 */
const SOCKET_EISCONN = 106;

/**
 * Transport endpoint is not connected.
 */
const SOCKET_ENOTCONN = 107;

/**
 * Cannot send after transport endpoint shutdown.
 */
const SOCKET_ESHUTDOWN = 108;

/**
 * Too many references: cannot splice.
 */
const SOCKET_ETOOMANYREFS = 109;

/**
 * Connection timed out.
 */
const SOCKET_ETIMEDOUT = 110;

/**
 * Connection refused.
 */
const SOCKET_ECONNREFUSED = 111;

/**
 * Host is down.
 */
const SOCKET_EHOSTDOWN = 112;

/**
 * No route to host.
 */
const SOCKET_EHOSTUNREACH = 113;

/**
 * Operation already in progress.
 */
const SOCKET_EALREADY = 114;

/**
 * Operation now in progress.
 */
const SOCKET_EINPROGRESS = 115;

/**
 * Is a named type file.
 */
const SOCKET_EISNAM = 120;

/**
 * Remote I/O error.
 */
const SOCKET_EREMOTEIO = 121;

/**
 * Quota exceeded.
 */
const SOCKET_EDQUOT = 122;

/**
 * No medium found.
 */
const SOCKET_ENOMEDIUM = 123;

/**
 * Wrong medium type.
 */
const SOCKET_EMEDIUMTYPE = 124;

const IPPROTO_IP = 0;

const IPPROTO_IPV6 = 41;

const SOL_TCP = 6;

const SOL_UDP = 17;

const IPV6_UNICAST_HOPS = 16;

const IPV6_RECVPKTINFO = 49;

const IPV6_PKTINFO = 50;

const IPV6_RECVHOPLIMIT = 51;

const IPV6_HOPLIMIT = 52;

const IPV6_RECVTCLASS = 66;

const IPV6_TCLASS = 67;

const SCM_RIGHTS = 1;

const SCM_CREDENTIALS = 2;

const SO_PASSCRED = 16;

const SOCKET_EPROCLIM = 10067;

const SOCKET_ESTALE = 10070;

const SOCKET_EDISCON = 10101;

const SOCKET_SYSNOTREADY = 10091;

const SOCKET_VERNOTSUPPORTED = 10092;

const SOCKET_NOTINITIALISED = 10093;

const SOCKET_HOST_NOT_FOUND = 11001;

const SOCKET_TRY_AGAIN = 11002;

const SOCKET_NO_RECOVERY = 11003;

const SOCKET_NO_DATA = 11004;

const SOCKET_NO_ADDRESS = 11004;

const AI_PASSIVE = 1;

const AI_CANONNAME = 2;

const AI_NUMERICHOST = 4;

const AI_ADDRCONFIG = 32;

const AI_NUMERICSERV = 1024;

const AI_V4MAPPED = 8;

const AI_ALL = 16;

/**
 * @since 8.1
 */
const TCP_DEFER_ACCEPT = 9;

/**
 * @since 8.2
 */
const SO_INCOMING_CPU = 49;

/**
 * @since 8.2
 */
const SO_MEMINFO = 55;

/**
 * @since 8.2
 */
const SO_BPF_EXTENSIONS = 48;

/**
 * @since 8.2
 */
const SKF_AD_OFF = -4096;

/**
 * @since 8.2
 */
const SKF_AD_PROTOCOL = 0;

/**
 * @since 8.2
 */
const SKF_AD_PKTTYPE = 4;

/**
 * @since 8.2
 */
const SKF_AD_IFINDEX = 8;

/**
 * @since 8.2
 */
const SKF_AD_NLATTR = 12;

/**
 * @since 8.2
 */
const SKF_AD_NLATTR_NEST = 16;

/**
 * @since 8.2
 */
const SKF_AD_MARK = 20;

/**
 * @since 8.2
 */
const SKF_AD_QUEUE = 24;

/**
 * @since 8.2
 */
const SKF_AD_HATYPE = 28;

/**
 * @since 8.2
 */
const SKF_AD_RXHASH = 32;

/**
 * @since 8.2
 */
const SKF_AD_CPU = 36;

/**
 * @since 8.2
 */
const SKF_AD_ALU_XOR_X = 40;

/**
 * @since 8.2
 */
const SKF_AD_VLAN_TAG = 44;

/**
 * @since 8.2
 */
const SKF_AD_VLAN_TAG_PRESENT = 48;

/**
 * @since 8.2
 */
const SKF_AD_PAY_OFFSET = 52;

/**
 * @since 8.2
 */
const SKF_AD_RANDOM = 56;

/**
 * @since 8.2
 */
const SKF_AD_VLAN_TPID = 60;

/**
 * @since 8.2
 */
const SKF_AD_MAX = 64;

/**
 * @since 8.2
 */
const TCP_CONGESTION = 13;

/**
 * @since 8.2
 */
const TCP_NOTSENT_LOWAT = 25;

/**
 * @since 8.2
 */
const TCP_KEEPIDLE = 4;

/**
 * @since 8.2
 */
const TCP_KEEPINTVL = 5;

/**
 * @since 8.2
 */
const TCP_KEEPCNT = 6;

/**
 * @since 8.3
 */
const TCP_QUICKACK = 12;

/**
 * @since 8.3
 */
const TCP_REPAIR = 19;

/**
 * Socket_set_option for the socket_send* functions.
 * It avoids copy b/w userland and kernel for both TCP and UDP protocols.
 * @since 8.2
 */
const SO_ZEROCOPY = 60;

/**
 * Socket_set_option for the socket_send* functions.
 * It avoids copy b/w userland and kernel for both TCP and UDP protocols.
 * @since 8.2
 */
const MSG_ZEROCOPY = 67108864;

/**
 * @since 8.4
 */
const SOCK_DCCP = 6;

/**
 * @since 8.4
 */
const TCP_SYNCNT = 7;

/**
 * @since 8.4
 */
const SOCK_CLOEXEC = 524288;

/**
 * @since 8.4
 */
const SOCK_NONBLOCK = 2048;

/**
 * @since 8.4
 */
const SO_BINDTOIFINDEX = 62;

/**
 * @since 8.5
 */
const AF_PACKET = 17;

const SO_BUSY_POLL = 46;

const IPPROTO_ICMP = 1;

const IPPROTO_ICMPV6 = 58;

const ETH_P_IP = 2048;

const ETH_P_IPV6 = 34525;

const ETH_P_LOOP = 96;

const ETH_P_ALL = 3;

const UDP_SEGMENT = 103;

const SHUT_RD = 0;

const SHUT_WR = 1;

const SHUT_RDWR = 2;

/**
 * @since 8.6
 */
const AF_UNSPEC = 0;

/**
 * @since 8.6
 */
const TCP_USER_TIMEOUT = 18;

/**
 * @since 8.6
 */
const EAI_ADDRFAMILY = -9;

/**
 * @since 8.6
 */
const EAI_AGAIN = -3;

/**
 * @since 8.6
 */
const EAI_ALLDONE = -103;

/**
 * @since 8.6
 */
const EAI_BADFLAGS = -1;

/**
 * @since 8.6
 */
const EAI_CANCELED = -101;

/**
 * @since 8.6
 */
const EAI_FAIL = -4;

/**
 * @since 8.6
 */
const EAI_FAMILY = -6;

/**
 * @since 8.6
 */
const EAI_IDN_ENCODE = -105;

/**
 * @since 8.6
 */
const EAI_INPROGRESS = -100;

/**
 * @since 8.6
 */
const EAI_INTR = -104;

/**
 * @since 8.6
 */
const EAI_NODATA = -5;

/**
 * @since 8.6
 */
const EAI_NONAME = -2;

/**
 * @since 8.6
 */
const EAI_NOTCANCELED = -102;

/**
 * @since 8.6
 */
const EAI_OVERFLOW = -12;

/**
 * @since 8.6
 */
const EAI_SERVICE = -8;

/**
 * @since 8.6
 */
const EAI_SOCKTYPE = -7;

/**
 * @since 8.6
 */
const EAI_SYSTEM = -11;
