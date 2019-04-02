//
//  pathdefs.lsl - part of pathfinding library
//
//  Makes Second Life pathfinding work reliably.
//
//  Animats
//  January, 2019
//  License: GPL
//  (c) 2019 John Nagle
//
//  Definitions common to multiple scripts
//
//  Constants
//
//  Pathmode - what we're doing now.
integer PATHMODE_OFF = 0;                                   // what we're doing now
integer PATHMODE_NAVIGATE_TO = 1;
integer PATHMODE_PURSUE = 2;
integer PATHMODE_WANDER = 3;
integer PATHMODE_EVADE = 4;
integer PATHMODE_FLEE_FROM = 5;
integer PATHMODE_CREATE_CHARACTER = 6;                      // create character, used at start
integer PATHMODE_UPDATE_CHARACTER = 7;                      // update character

list PATHMODE_NAMES = ["Off", "Navigate to", "Pursue", "Wander", "Evade", "Flee", "Create", "Update"];  // for messages
//
//  Path statuses.  Also, the LSL PU_* pathfinding statuses are used
integer PATHSTALL_NONE = -1;                                // not stalled, keep going
integer PATHSTALL_RETRY = -2;                               // unstick and retry
integer PATHSTALL_STALLED = -3;                             // failed, despite retries
integer PATHSTALL_CANNOT_MOVE = -4;                         // can't move at all at current position
integer PATHSTALL_NOPROGRESS = -5;                          // not making progress, fail
integer PATHSTALL_UNSTICK = -6;                             // stuck, need to try an unstick
integer PATHSTALL_UNREACHABLE = -7;                         // pursue did not start, unreachable				                

//  Error levels
integer PATH_MSG_ERROR = 0;
integer PATH_MSG_WARN = 1;
integer PATH_MSG_INFO = 2;
//
//  Message direction (because both ends see a reply)
integer PATH_DIR_REQUEST = 101;                             // application to path finding script
integer PATH_DIR_REPLY = 102;                               // reply coming back