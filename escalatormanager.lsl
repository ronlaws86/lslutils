//
//  Escalator manager
//
//  Rezzes and aligns an object from this object's content.
//  Handles resizing.
//
//  This is for objects which have an associated object which cannot be made a child,
//  cannot be made a prims, usually
//  because they are for keyframe animation.
//
//  Configuration
//
//  Additional object we must rez.
//
//  SINGLE SIZE VERSION for escalator - no resizing yet
//
//  Positions captured from the edit window of a successful assembly.
//
//// CHILDPOS = <233.19861, 50.00000, 37.93129>;
//// PARENTPOS = <233.00000, 50.00000, 38.15352>;
//// CHILDOFFSET = <0.19861, 0.0, -0.222> // need to swap axes
integer STEPSANIMLINK = 2;
integer STEPSANIMFACE = ALL_SIDES;
integer RAILANIMLINK = 1;
integer RAILANIMFACE = 3;
integer TRAFFICLIGHTLINK = 1;
integer TRAFFICLIGHTFACE = 4;

float STEPSANIMRATE = -1.5;                         // steps animation speed
float RAILANIMRATE = 0.9;                           // railing animation speed, matched to escalator
float TRAFFICLIGHTGLOW = 0.2;                       // glow brightness for red and green lights

vector CHILDOFFSET = <0.0, 0.19861, -0.222>;    // root of child rel to self

string OBJECTNAME = "Steps";
vector INITIALROTANG = <0,0,0>;                 // initial rotation angle, radians

integer MAXINT = 16777216;                      // 2^24
integer MINCHAN = 100000;                       // for range of allowed unique channel numbers
integer COMMANDCHANNEL = -8372944;              // randomly chosen channel. Not secret


string SOUNDNAME="escalator1";          // escalator sound effect
float VOLUME=0.20;                      // audio level


//  Global variables
integer gRezzedObjectID = 0;            // channel for deleting rezzed object
vector gPrevPos = ZERO_VECTOR;
rotation gPrevRot = ZERO_ROTATION;
integer gDirection = 0;                 // direction of motion (-1, 0, or +1)
integer gLastDirection = 1;             // last moving direction. Remote uses this.
integer gLocked = FALSE;                // owner only
integer gDialogChannel;                 // for talking to user
integer gDialogHandle = 0;              // listening for dialog response
vector gScale = ZERO_VECTOR;            // scale of object
integer gCommandHandle = 0;             // for command listener

//
//  vector_mult - multiply vector by vector elementwise
//
vector vector_mult(vector v0, vector v1)
{   return (<v0.x*v1.x, v0.y*v1.y, v0.z*v1.z>); }// there should be a builtin for this

//
//  setup_command_listen -- start listening for commands from a remote control
//
setup_command_listen()
{  
    llListenRemove(gCommandHandle);                  // kill any existing listen
    gCommandHandle = llListen(COMMANDCHANNEL,"", "","");    // listen on command channel
}
    
command_listen(integer channel, string msgname, key id, string message)
{
    key ownerkey = llGetOwnerKey(id);                       // owner of sender of message
    ////llOwnerSay(message + " from " + (string)id + " owned by " + (string)ownerkey);
    if (ownerkey != llGetOwner()) { return; }               // ignore if msg not from owner
    ////llOwnerSay(message);
    string request = llJsonGetValue(message, ["request"]);
    if (request == JSON_NULL || request == JSON_INVALID)  { return; }                  // return silently if not "request"
    string name = llJsonGetValue(message, ["name"]);
    string id = llJsonGetValue(message, ["id"]);
    string dir = llJsonGetValue(message, ["dir"]); 
    //  To match, the request must either match on ID, or the name in the request must be
    //  a substring of our object name. Case insensitive match.
    if ((name == JSON_INVALID || name == JSON_NULL)   // JSON parse failed
            || (llSubStringIndex(llToLower(llGetObjectName()), llToLower(name)) < 0 && id != (string)llGetKey()))
    {   llOwnerSay("Message not for us: " + message); return; }
    do_command(request, dir);                                    // do the command        
}

dialog_listen(integer channel, string name, key id, string message)
{
    llListenRemove(gDialogHandle);              // turn off the listener
    ////llOwnerSay("Dialog string: " + name + " message: " + message);
    //  Process response
    integer direction = gDirection;
    if (llSubStringIndex(message, "Up") >= 0) { direction = 1; }
    else if (llSubStringIndex(message, "Down") >= 0) { direction = -1; }
    else if (llSubStringIndex(message, "Stop") >= 0) { direction = 0; }
    else if (llSubStringIndex(message, "Lock") >= 0) { gLocked = !gLocked; } 
    set_escalator_state(direction);             // control the escalator
}

//
//  do the command from the remote control
//
do_command(string request, string dir)
{   if (request == "start")
    {   if (dir == "1" || dir == "-1") { gLastDirection = (integer) dir; }    // set dir if specified
        set_escalator_state(gLastDirection); // restart in previous direction
    } else if (request == "stop")
    {   set_escalator_state(0);             // stop 
    } else if (request == "status")         // just report current condition
    {
        string stat = "stopped";
        if (gDirection != 0)
        {   stat = "running";                               // true if running
        }
        //  Tell remote controller what we are doing.
        llShout(COMMANDCHANNEL, llList2Json(JSON_OBJECT, ["reply", "status", "status", stat, "dir", (string) gDirection, "name", llGetObjectName()]));                          
    } else {   llShout(COMMANDCHANNEL, llList2Json(JSON_OBJECT, ["reply", "error", "error", "Invalid request:" + request]));}
    
}

//
//  set_traffic_light -- set traffic lights to up, down, or stop.
//
set_traffic_light(integer dir)
{   float texyoffset = 0;                   // the texture has 4 lights in 4 quadrants
    float texxoffset = 0.5;                 // show lights as dark     
    float glow = 0.0;                       // no glow
    integer fullbright = FALSE;
    if (dir < 0)                            // down
    {   texyoffset = 0.5;                   // reverses red and green
        texxoffset = 0.0;                    // red/green area of texture
        glow = TRAFFICLIGHTGLOW;            // glow on
        fullbright = TRUE;                  // emit light
    } else if (dir > 0)                     // up 
    {   texyoffset = 0.0; 
        texxoffset = 0.0;                   // red/green area of texture
        glow = TRAFFICLIGHTGLOW;
        fullbright = TRUE;
    } 
    llOffsetTexture(texxoffset, texyoffset, TRAFFICLIGHTFACE);  // selects proper area of texture
    llSetLinkPrimitiveParamsFast(TRAFFICLIGHTLINK,              // sets full bright and glow
        [PRIM_FULLBRIGHT, TRAFFICLIGHTFACE, fullbright, 
        PRIM_GLOW, TRAFFICLIGHTFACE, glow]);
}

set_escalator_state(integer direction)
{
    if (direction == gDirection) { return; }    // no change in dir
    gDirection = direction;                     // change direction
    ////llOwnerSay("Step direction: " + (string)gDirection);   
    llShout(gRezzedObjectID, llList2Json(JSON_OBJECT,
        ["command","DIR", "direction", (string)gDirection]));
    //  Animation of flat steps which are part of the escalator base and do not move.
    if (gDirection != 0)
    {   llSetLinkTextureAnim(RAILANIMLINK, ANIM_ON|LOOP|SMOOTH, 
                RAILANIMFACE, 1, 1, 1.0, -1.0, RAILANIMRATE*gDirection);
        llSetLinkTextureAnim(STEPSANIMLINK, ANIM_ON|LOOP|SMOOTH, 
                STEPSANIMFACE, 1, 1, 1.0, -1.0, STEPSANIMRATE*gDirection); // start animation
        llLoopSound(SOUNDNAME, VOLUME);                 // escalator sound 
    }
    else
    {   
        llSetLinkTextureAnim(RAILANIMLINK, 0, RAILANIMFACE, 1, 1, 1.0, -1.0, 0); // stop previous animation
        llSetLinkTextureAnim(STEPSANIMLINK, 0, STEPSANIMFACE, 1, 1, 1.0, -1.0, 0); // stop previous animation
        llStopSound();                                  // silence
    }
    set_traffic_light(gDirection);                      // set green and red lights
    string stat = "stopped";
    if (gDirection != 0)
    {   stat = "running";                               // true if running
        gLastDirection = direction;                     // for remote stop/start
    }
    //  Tell remote controller what we are doing.
    llShout(COMMANDCHANNEL, llList2Json(JSON_OBJECT, ["reply", "status", "status", stat, "dir", (string) gDirection, "name", llGetObjectName()]));                          
}
//
//  place_object -- rez and place object
//
place_object(string name, vector offset)
{
    //  Delete old object
    if (gRezzedObjectID) 
    {   
        llShout(gRezzedObjectID, llList2Json(JSON_OBJECT,["command","DIE"]));
    }
    //  Rez new object
    rotation rot = llGetRot();
    rot = rot * llEuler2Rot(INITIALROTANG*DEG_TO_RAD); // rotate before rezzing
    offset = offset * rot;              // to world coords
    vector pos = llGetPos() + offset;
    //  unique integer channel number in range frand can handle
    integer randomid = - (integer)(llFrand(MAXINT-MINCHAN) + MINCHAN); 
    llRezObject(name, pos, <0,0,0>, rot, randomid); // create the object
    gRezzedObjectID = randomid;
    gPrevPos = llGetPos();                  // previous location
    gPrevRot = llGetRot();
    ////llOwnerSay("Placed " + name + " id: " + (string) randomid); // ***TEMP***
    llSleep(3.0);                           // allow object time to rez
    llShout(gRezzedObjectID, llList2Json(JSON_OBJECT,
        ["command","DIR", "direction", (string)gDirection]));
}

move_check() 
{   //  Check whether escalator moved. via edit.
    if ((llVecMag(llGetPos()-gPrevPos) > 0.001)     // if we moved, delete and replace object
    || (llFabs(llAngleBetween(llGetRot(),gPrevRot)) > 0.0005))
    {
        vector objectoffset = CHILDOFFSET;     // offset for new object
        place_object(OBJECTNAME, objectoffset);
    }
}

default
{
    state_entry()
    {   gScale = llGetScale();                          // save object size
        setup_command_listen();
        gDialogChannel = - (integer)(llFrand(MAXINT-MINCHAN) + MINCHAN);  // for dialog msgs
        vector objectoffset = CHILDOFFSET;              // offset for new object
        place_object(OBJECTNAME, objectoffset);
        gDirection = 0;                                 // not running
        llSetLinkTextureAnim(STEPSANIMLINK, 0, STEPSANIMFACE, 1, 1, 1.0, -1.0, 0); // stop previous animation
        llSetLinkTextureAnim(RAILANIMLINK, 0, RAILANIMFACE, 1, 1, 1.0, -1.0, 0); // stop previous animation
        llStopSound();                                  // silence
        set_traffic_light(0);                           // set green and red lights                           
    }

    collision_start(integer total_number)               // using it forces a recheck
    {
        move_check();                                   // moved by editing?
    }
    
    on_rez(integer rezid) 
    {   llResetScript();
    }
    
    touch_start(integer num_detected)           // user interface
    {   
        key toucherID = llDetectedKey(0);       // who touched?
        move_check();                           // check if moved before dialog
        if (gLocked && (toucherID != llGetOwner())) { return; } // ignore touch if locked and not owner
        llListenRemove(gDialogHandle);          // remove any old listener
        list choices = [];                      // dialog box option
        if (gDirection == 1) { choices += "⬤ Up"; } else {choices += "Up"; }
        if (gDirection == -1) { choices += "⬤ Down"; } else {choices += "Down"; }
        if (gDirection == 0) { choices += "⬤ Stop"; } else {choices += "Stop"; }
        if (gLocked) { choices += "☑ Locked"; } else {choices += "☐ Locked"; }
        llDialog(toucherID, "Escalator control", choices, gDialogChannel);
        gDialogHandle = llListen(gDialogChannel, "", toucherID, ""); // wait for dialog
        llSetTimerEvent(60.0);                  // just for cleanup
    }
        
    listen(integer channel, string name, key id, string message)
    {
        if (channel == COMMANDCHANNEL)                                  // remote control listen
        {   command_listen(channel, name, id, message); }
        else if (channel == gDialogChannel)                             // dialog listen
        {   dialog_listen(channel, name, id, message); }
        else 
        {   llSay(DEBUG_CHANNEL, "Unexpected message on channel " + (string)channel + ": " + message); }
    }
    

    timer()
    {   // dialog listener cleanup
        llSetTimerEvent(0); 
        llListenRemove(gDialogHandle);
    }
    
    changed(integer change)
    {   if (change & CHANGED_SCALE)                     // can't do that
        {   llSay(0,"Cannot change size of this object.");
            llSetScale(gScale);                         // resizing this would break it
        }
        if (change & CHANGED_OWNER) { setup_command_listen(); }    // reset who we listen to on ownership change
    }
}
