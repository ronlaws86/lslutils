//
//  assert.lsl -- general assert include
//
#ifndef ASSERTLSL                                           // compile guard
#define ASSERTLSL
//
//  panic - abort with message, restarting script
//
panic(string msg)
{   msg = "PANIC: " + msg;
    llOwnerSay(msg);                                        // tell owner
    llSay(DEBUG_CHANNEL, msg);                              // tell nearby
    llMessageLinked(LINK_SET, DEBUG_CHANNEL, msg, "");      // tell other scripts we aborted so they can reset
    llSleep(1.0);                                           // wait for message propagation
    llResetScript();                                        // reset this script
}

#define assert(exp) { if (!(exp)) { panic("Assertion failed at " + __SHORTFILE__ + " line " + (string) __LINE__); }}

//  Obsolete, remove once calls are gone.
#ifdef DEBUG
#define DEBUGPRINT(s) // Nothing for now
#define DEBUGPRINT1(s) llOwnerSay((s))
#else // not debugging
#define DEBUGPRINT(s) {}
#define DEBUGPRINT1(s) {}
#endif // DEBUG

#endif // ASSERTLSL
