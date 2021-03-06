//
//
//  pathstart.lsl -- startup section of new pathfinding system
//
//  Called by user task which imports pathcall. Handles
//  startup and retry.
//
//  Animats
//  November, 2019
//
//  License: GPLv3.
//
#include "npc/patherrors.lsl"
#include "npc/pathbuildutils.lsl"
//

//  Constants
#define TESTSPACING (0.33)                                      // (m) vertical spacing between ray casts
#define PATHMAXRETRIES  3                                       // (count) no more than this many retries before giving up

//
//  Globals
//  Character parameters
float gPathcallTurnspeed = 0.1;
//  Retry state
integer gPathcallRetries = 0;                                   // no retries yet
integer gPathcallStarttime = 0;                                 // time request started
float gPathcallLastDistance = 0.0;                              // distance to goal on last try
list  gPathcallLastParams = [];                                 // params at last try

integer gPathcallReset = FALSE;                                 // have we reset the system since startup?

integer gLocalPathId = 0;                                       // current path serial number
integer gLocalRequestId = 0;                                    // current request from user serial number

//
//  pathLinkMsg -- reply coming back from path execution
//
pathLinkMsg(string jsn, key hitobj)
{   
    integer status = (integer)llJsonGetValue(jsn, ["status"]);  // status and pathid via JSON.
    integer pathid = (integer)llJsonGetValue(jsn, ["pathid"]);  // hitobj as key param in link message
    if (pathid != gLocalPathId)                         // result from a cancelled operation
    {   pathMsg(PATH_MSG_WARN, "Stale path completed msg #" + 
            (string)pathid + "(expected #" + (string)gLocalPathId + "), status " + (string)status + " discarded.");
        if (pathid > gLocalPathId) { pathMsg(PATH_MSG_ERROR,"Path completed pathid too large."); }  // ***TEMP***    out of sync          
        return;
    }
    pathMsg(PATH_MSG_NOTE,"Path complete, status " + (string)status + ", hitobj: " + (string)hitobj + " Time: " + (string)llGetTime());
    if (pathretry(status, hitobj)) { return; }          // attempt a retry
    pathUpdateCallback(status, hitobj);
}

//
//  pathprepstart -- start the path planner task
//
pathprepstart(key target, vector regioncorner, vector goal, float stopshort, float speed, float testspacing, integer pathid)
{   
    string jsn = llList2Json(JSON_OBJECT,
        ["request","pathprep", "pathid", pathid,
        "target",target, "regioncorner", regioncorner, "goal", goal, "stopshort", stopshort, "testspacing", testspacing,
        "speed", speed, "turnspeed", gPathcallTurnspeed, "starttime", gPathcallStarttime]);
    pathMsg(PATH_MSG_NOTE,"Path prep start: " + jsn);
    llMessageLinked(LINK_THIS, PATHPLANREQUEST, jsn,"");   // send to path prep 
}
//
//  pathbegin -- go to indicated point or target. Internal fn.
//
//  Go to the indicated location, in the current region, avoiding obstacles.
//
//  Stop short of the target by the distance stopshort. This can be zero. 
//
pathbegin(key target, vector regioncorner, vector endpos, float stopshort, float speed, integer requestid)
{
    gPathcallLastDistance = INFINITY;                               // must get shorter on each retry
    gPathcallRetries = 0;                                           // no retries yet
    gPathcallStarttime = llGetUnixTime();                           // time entire sequence started, before retries
    gLocalRequestId = requestid;                                    // save request ID for callbacks
    llResetTime();                                                  // for elapsed time display
    pathstart(target, regioncorner, endpos, stopshort, speed);            // do it
}
//
//  pathstart -- go to indicated point or target. Internal fn. Used by begin or restart
//
//  Go to the indicated location, in any nearby region, avoiding obstacles.
//
//  Stop short of the target by the distance stopshort. This can be zero. 
//
pathstart(key target, vector goalregioncorner, vector endpos, float stopshort, float speed)
{   assert(gPathWidth > 0);                                         // we must be initialized
    gPathcallLastParams = [];                                       // no params for retry stored yet.
    gLocalPathId = (gLocalPathId+1)%(PATHMAXUNSIGNED-1);            // our serial number, nonnegative
    if (target != NULL_KEY)                                         // if chasing a target
    {   list details = llGetObjectDetails(target, [OBJECT_POS]);    // get object position
        if (details == [])                                          // target has disappeared
        {   pathdonereply(PATHERRTARGETGONE,target,gLocalPathId);  // send message to self and quit
            return;
        }
        endpos = llList2Vector(details,0);                          // use this endpos
        goalregioncorner = llGetRegionCorner();                     // relative to our own region
        llOwnerSay("Position of target " + llKey2Name(target) + " is " + (string)endpos); // ***TEMP***
    }
    //  Are we allowed to go to this destination?
    assert(endpos != ZERO_VECTOR);                                  // both must be nonzero here
    assert(goalregioncorner != ZERO_VECTOR);
    vector relendpos = endpos + llGetRegionCorner() - goalregioncorner;     // relative to current region 
    if (pathisinregion(relendpos) && !pathvaliddest(relendpos))     // allow blind move to off-region destination
    {   pathMsg(PATH_MSG_WARN,"Destination " + (string)relendpos + " not allowed."); 
        pathdonereply(PATHERRBADDEST,NULL_KEY,gLocalPathId);         // send message to self to report error
        return; 
    }
    gPathcallLastParams = [target, goalregioncorner, endpos, stopshort, speed];      // save params for restart
    //  Find walkable under avatar. Look straight down. Endpos must be close to navmesh or llGetStaticPath will fail.
    float newz = endpos.z;
    if (llGetRegionCorner() == goalregioncorner)                      // only try this if not crossing regions
    {   newz = pathfindwalkable(relendpos, 0.0, gPathHeight*3);  }    // find walkable below char
    if (newz < 0)
    {   pathMsg(PATH_MSG_WARN,"Cannot find walkable surface under goal near "+ (string)relendpos); 
        vector navmeshpos = pathnearestpointonnavmesh(relendpos);      // look for nearest point on navmesh (expensive)
        if (navmeshpos == ZERO_VECTOR)                                 // no navmesh near endpos
        {   pathMsg(PATH_MSG_WARN, "Cannot find navmesh under goal, fails.");
            pathdonereply(PATHERRBADDEST,NULL_KEY,gLocalPathId);       // send message to self to report error
            return; 
        }
        endpos = navmeshpos;
    } else {
        endpos.z = newz;                                                // use ground level found by ray cast
    }
    //  Generate path
    pathprepstart(target, goalregioncorner, endpos, stopshort, speed, TESTSPACING, gLocalPathId);
    //  Output from pathcheckobstacles is via callbacks
}
//
//  pathturn -- turn in place request 
//
pathturn(float heading)
{
    gLocalPathId = (gLocalPathId+1)%(PATHMAXUNSIGNED-1);        // increment our serial number, nonnegative
    string params = llList2Json(JSON_OBJECT,
        ["request","pathturn",
         "heading",heading,
         "pathid", gLocalPathId]);
    llMessageLinked(LINK_THIS, PATHPLANREQUEST, params,"");     // send to path prep 
}
//
//  pathretry -- check if path can be retried
//
integer pathretry(integer status, key hitobj)
{
    if (llListFindList(PATHRETRYABLES, [status]) < 0) { return(FALSE); }// not retryable
    if (gPathcallLastParams == []) { return(FALSE); }                   // no retry params
    key target = llList2Key(gPathcallLastParams,0);                     // get retry params back
    vector goalregioncorner = llList2Vector(gPathcallLastParams,1);     // region corner
    vector endpos = llList2Vector(gPathcallLastParams,2);               // this language needs structures
    float shortstop = llList2Float(gPathcallLastParams, 3);
    float speed = llList2Float(gPathcallLastParams,4);
    gPathcallLastParams = [];                                           // consume retry params to prevent loop
    if (gPathcallRetries > PATHMAXRETRIES)
    {   pathMsg(PATH_MSG_WARN, "Maximum retries exceeded.");            // not getting anywhere, give up and report trouble
        return(FALSE);                                                  // 
    }
    vector relendpos = endpos;
    if (goalregioncorner != ZERO_VECTOR)
    {   relendpos += goalregioncorner - llGetRegionCorner(); }             // adjust endpos for region cross
    float dist = pathdistance(llGetRootPosition()-<0,0,gPathHeight*0.45>, relendpos, gPathWidth, CHARACTER_TYPE_A);  // measure distance to goal at gnd level
    if (dist < 0 || dist >= gPathcallLastDistance)                      // check for closer. negative means path distance failed. Avoids loop.
    {   if (status != PATHERRTARGETMOVED)                               // but keep pursuing if target is moving
        {   pathMsg(PATH_MSG_WARN, "No retry, did not get closer. Distance " + (string)dist + "m."); return(FALSE); }   // cannot retry  
    }
    if (gPathcallLastDistance > dist) { gPathcallLastDistance = dist; } // use new value if smaller, so the initial value of infinity gets reduced
    //  Must do a retry
    gPathcallRetries++;                                                 // retry count 
    pathMsg(PATH_MSG_WARN, "Retrying. Distance " + (string)dist + "m. Retry " + (string)gPathcallRetries);                              // retry
    pathstart(target, goalregioncorner, endpos, shortstop, speed);          // trying again
    return(TRUE);                                                       // doing retry, do not tell user we are done.
}

//
//  pathUpdateCallback -- pass callback info back to calling user program
//
pathUpdateCallback(integer status, key hitobj)
{   
    llMessageLinked(LINK_THIS,PATHSTARTREPLY,
        llList2Json(JSON_OBJECT,["reply","pathbegin","requestid", gLocalRequestId, "status",status]),hitobj); 
}
//
//  Main program
//
default
{
    state_entry()
    {   pathinitutils();                        // library init
    }

    //
    //  Incoming link message - will be a plan job request, stop, or speed set
    //    
    link_message(integer status, integer num, string jsn, key id)
    {   if (num == PATHSTARTREQUEST)                                     // if request for a planning job
        {   pathMsg(PATH_MSG_NOTE,"Path request:" + jsn);
            integer requestid = (integer)llJsonGetValue(jsn,["requestid"]); // caller controls the path serial number
            string request = llJsonGetValue(jsn,["request"]);           // get request type
            if (request == "pathbegin")                                 // common start function
            {   vector regioncorner = (vector)llJsonGetValue(jsn,["regioncorner"]); 
                vector goal = (vector)llJsonGetValue(jsn,["goal"]);     // get goal point
                key target = (key)llJsonGetValue(jsn,["target"]);  // get target if pursue
                float stopshort = (float)llJsonGetValue(jsn,["stopshort"]);
                float speed = (float)llJsonGetValue(jsn,["speed"]);
                pathbegin(target, regioncorner, goal, stopshort, speed, requestid);    // start movement
            } else if (request == "pathstop")
            {   pathbegin(NULL_KEY,ZERO_VECTOR,llGetRootPosition(),100.0, 1.0, requestid);    // a stop is a dummy move to self
            } else if (request == "pathspeed")
            {   ////gPathcallSpeed = (float)llJsonGetValue(jsn,["speed"]);
                gPathcallTurnspeed = (float)llJsonGetValue(jsn,["turnspeed"]);
            } else if (request == "pathturn")
            {   pathturn((float)llJsonGetValue(jsn,["heading"]));
            } else {
                panic("Unknown path request: " + jsn);                  // unlikely
            }
        } else if (num == PATHPLANREPLY)                                // reply from planner
        {   pathLinkMsg(jsn,id);                                        // will retry, or will reply to user
        } else if (num == PATHPARAMSINIT)
        {   pathinitparams(jsn);                                        // initialize params
        } else if (num == DEBUG_MSGLEV_BROADCAST)               // set debug message level for this task
        {   debugMsgLevelSet(jsn);
        }
    }
}
             






