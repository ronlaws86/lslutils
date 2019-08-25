//
//
//  pathcall.lsl -- caller interface to new pathfinding system
//
//  Animats
//  August, 2019
//
//  License: GPLv3.
//
#include "npc/patherrors.lsl"
#include "npc/pathbuildutils.lsl"
//
#ifdef OBSOLETE
//  Message direction (because both ends see a reply)
integer PATH_DIR_REQUEST = 101;                                 // application to path finding script
integer PATH_DIR_REPLY = 102;                                   // reply coming back
integer PATH_DIR_REPLY_TICK = 103;                              // reply indicating other end is still alive
//
integer PATH_MIN_IM_INTERVAL = 3600;                            // seconds between IMs. Do not overdo.
#endif // OBSOLETE

//  Constants
float REGION_SIZE = 256.0;                                      // size of a region   
//
//  Globals
//  Character parameters
float gPathcallWidth = 1.0;                                     // these are overrridden at init
float gPathcallHeight = 1.0;
float gPathcallSpeed = 1.0;                                     // speed defaults are very slow
float gPathcallTurnspeed = 0.1;
integer gPathcallChartype = CHARACTER_TYPE_A;                   // humanoid

//
//   pathLinearInterpolate  -- simple linear interpolation
//
float pathLinearInterpolate(float n1 , float n2 , float fract )
{   return n1 + ( (n2-n1) * fract );    } 

//
//  easeineaseout  --  interpolate from 0 to 1 with ease in and ease out using cubic Bezier.
//
//  ease = 0: no smoothing
//  ease = 0.5: reasonable smoothing
//
float easeineaseout(float ease, float fract)
{   float ym = pathLinearInterpolate( 0 , fract, fract );
    float yn = pathLinearInterpolate(fract , 1 , fract );
    float y = pathLinearInterpolate( ym , yn , fract);
    return(y);
}


//
//  pathFaceInDirection  --  face in desired direction
//
//  Uses llSetRot. OK to use on characters when no pathfinding operation is in progress.
//
pathFaceInDirection(vector lookdir)
{   float TURNRATE = 90*DEG_TO_RAD;                             // (deg/sec) turn rate
    float   PATH_ROTATION_EASE = 0.5;                           // (0..1) Rotation ease-in/ease out strength
    lookdir.z = 0.0;                                            // rotate about XY axis only
    rotation endrot = llRotBetween(<1,0,0>,llVecNorm(lookdir)); // finish here
    rotation startrot = llGetRot();                             // starting from here
    float turntime = llFabs(llAngleBetween(startrot, endrot)) / TURNRATE;  // how much time to spend turning
    integer steps = llCeil(turntime/0.200 + 0.001);             // number of steps 
    integer i;
    for (i=0; i<= steps; i++)                                   // turn in 200ms steps, which is llSetRot delay
    {   float fract = ((float)i) / steps;                       // fraction of turn (0..1)
        float easefract = easeineaseout(PATH_ROTATION_EASE, fract); // smooth acceleration
        llSetRot(slerp(startrot, endrot, easefract));           // interpolate rotation
    }
}
//
//  User API functions
//
//  ***SOME NOT YET IMPLEMENTED***
//
//  pathInit -- sets up the path planning system
//
//  Sets up the path planning system. 
//  width and height are the dimensions of the character. 
//  chartype is the pathfinding type of the character,
//  usually **CHARACTER_TYPE_A** for humanoid forms taller than they are wide.

//  The width and height define a vertical cylinder
//  around the character's center. The character's collision model must fit within cylinder. 
//  If it does not, the character will bump into obstacles and stop.
//
pathInit(float width, float height, integer chartype, integer msglev)
{
    gPathMsgLevel = msglev;                     // set error message level (PATH_MSG_INFO, etc.)
    gPathcallWidth = width;                         // character params
    gPathcallHeight = height;
    gPathcallChartype = chartype;
}

//
//  pathSpeed -- set linear and turn speed for future moves
//
//
//  speed is in meters per second. Reasonable values are 0.5 to 4.
//  Ordinary walking speed in Second Life is 1.5 meters/sec.
//
//  turnspeed is the turning speed when changing direction, in radians per second.
//  0.2 is a reasonable value. When in a path segment with both moving and turning,
//  movement speed is slowed to allow the turn to complete at the usual turn rate.
//  So characters slow down when turning corners.
//
pathSpeed(float speed, float turnspeed)
{   gPathcallSpeed = speed;
    gPathcallTurnspeed = turnspeed;
}


//
//  pathStop -- stop current operation
//
//  A new command can then be sent. 
//  This is not usually necessary.
//  Sending a command while one is already running will stop 
//  the current movement, although not instantly.
//
//  ***UNIMPLEMENTED***
//
pathStop()
{}

//
//  pathTick -- call every few seconds when running the path system.
//
//  This is used only for a stall timer.
//
//  ***UNIMPLEMENTED***
//
pathTick(){}

//
//  pathNavigateTo -- go to indicated point
//
//  Go to the indicated location, in the current region, avoiding obstacles.
//
//  Stop short of the target by the distance stopshort. This can be zero. 
//
pathNavigateTo(vector endpos, float stopshort)
{
    vector startpos = llGetPos();
    vector startscale = llGetScale();
    gLocalPathId++;                                     // our serial number, passed forward
    startpos.z = (startpos.z - startscale.z*0.5);       // ground level for start point
    //  Find walkable under avatar. Look straight down. Startpos must be on ground.
    endpos = pathfindwalkable(endpos, gPathcallHeight);      // find walkable below char
    if (endpos == ZERO_VECTOR)
    {   pathMsg(PATH_MSG_WARN,"Error looking for walkable under goal."); 
        llMessageLinked(LINK_THIS, PATH_DIR_REPLY, (string)PATHEXENOTWALKABLE, ""); // send message to self to report error
        return; 
    }
    //  Generate path.
    pathplanstart(startpos, endpos, gPathcallWidth, gPathcallHeight, stopshort, gPathcallChartype, TESTSPACING, gLocalPathId);    
    //  Output from pathcheckobstacles is via callbacks
}

//
//  pathPursue -- go to target avatar. No real pursuit for now.
//
//
//  Pursue the object target, usually an avatar.
//  Stop short of the target by the distance stopshort, so as not to get in the avatar's face.
//  1.75 to 2.0 meters is a reasonable social distance for stopshort.
//  This just does a pathNavigateTo to the target's current location.
//  If the target moves, the character's course does not change. 
//  (This may be improved in later versions.)
//
pathPursue(key target, float stopshort)
{
    list details = llGetObjectDetails(target, [OBJECT_POS]);    // get object position
    vector endpos = llList2Vector(details,0);
    pathNavigateTo(endpos, stopshort);                          // head there
}

pathLinkMsg(integer sender_num, integer num, string msg, key hitobj)
{   
    if (num == PATH_DIR_REPLY)
    {   integer status = (integer)msg;
        pathMsg(PATH_MSG_WARN,"Path complete, status " + (string)status + " Time: " + (string)llGetTime());
        ////integer callbackstat = PU_GOAL_REACHED;         // normal status
        ////if (status != 0) { callbackstat =  PU_FAILURE_UNREACHABLE; } // for now, not analyzing why
        pathUpdateCallback(status, hitobj);
    }
}

integer gLocalPathId = 0;                                   // path serial number

//
//  pathfindwalkable -- find walkable below avatar
//
//  Looks straight down.
//  Returns ZERO_VECTOR if fail.
//
vector pathfindwalkable(vector startpos, float height)
{   //  Look downward twice the height, because of seat mispositioning issues.
    list hits = llCastRay(startpos, startpos - <0,0,height*3>, 
            [RC_MAX_HITS,10, RC_REJECT_TYPES, RC_REJECT_PHYSICAL]); // go down up to 5 objs
    pathMsg(PATH_MSG_INFO,"Walkable hits looking down from " + (string)startpos + ": " + llDumpList2String(hits,",")); // ***TEMP***
    integer hitstatus = llList2Integer(hits,-1);        // < 0 is error
    if (hitstatus < 0)
    {   pathMsg(PATH_MSG_ERROR,"Error looking for walkable below " + (string)startpos); return(ZERO_VECTOR); }
    integer i;
    for (i=0; i<hitstatus*2; i = i + 2)                         // search hits
    {   key hitobj = llList2Key(hits,i);
        vector hitpt = llList2Vector(hits, i+1);
        string name = "Ground"; // ***TEMP***
        if (hitobj != NULL_KEY) // ***TEMP***
        {   name = llList2String(llGetObjectDetails(hitobj,[OBJECT_NAME]),0);} // ***TEMP***
        pathMsg(PATH_MSG_INFO,"Walkable test: " + (string)hitpt + " (" + name + ")");         // ***TEMP***
        if (hitobj == NULL_KEY) { return(hitpt); }               // found ground
        list details = llGetObjectDetails(hitobj, [OBJECT_PATHFINDING_TYPE]);
        integer pathfindingtype = llList2Integer(details,0);    // get pathfinding type
        if (pathfindingtype == OPT_WALKABLE) { return(hitpt); } // found walkable
    }     
    return(ZERO_VECTOR);                                        // no find
}


//
//  pathplanstart -- start the path planner task
//
pathplanstart(vector startpos, vector goal, float width, float height, float stopshort, integer chartype, float testspacing, integer pathid)
{
    string params = llList2Json(JSON_OBJECT, 
        ["startpos",startpos, "goal", goal, "stopshort", stopshort, "width", width, "height", height, "chartype", chartype, "testspacing", testspacing,
        "speed", gPathcallSpeed, "turnspeed", gPathcallTurnspeed,
        "pathid", pathid, "msglev", gPathMsgLevel]);
    llMessageLinked(LINK_THIS, PATH_DIR_REQUEST, params,"");   // send to planner  
}


//  Usual SLERP function for quaternion interpolation
rotation slerp(rotation a, rotation b, float t) {
   return llAxisAngle2Rot( llRot2Axis(b /= a), t * llRot2Angle(b)) * a;
}    

integer rand_int(integer bound)                 // bound must not exceed 2^24.
{   return((integer)llFrand(bound)); }          // get random integer                   

vector vec_to_target(key id)         
{   return(target_pos(id) - llGetPos());   }         

vector target_pos(key id)
{   list v = llGetObjectDetails(id, [OBJECT_POS]);  
    if (v == []) { return(ZERO_VECTOR); }         // not really a good choice for fails  
    return(llList2Vector(v,0));                             
}

vector dir_from_target(key id)                      
{
    list r = llGetObjectDetails(id, [OBJECT_ROT]);  
    if (r == []) { return(ZERO_VECTOR); }           
    rotation arot = llList2Rot(r,0);                
    vector facingdir = <1,0,0>*arot;
    facingdir.z = 0.0;                              
    return(llVecNorm(facingdir));                   
}

//
//  valid_dest - is target valid (same sim and same parcel ownership?)
//
integer valid_dest(vector pos) 
{
    if (pos.x <= 0 || pos.x >= REGION_SIZE || pos.y <= 0 || pos.y >= REGION_SIZE) { return(FALSE); }
    list theredata = llGetParcelDetails(pos, [PARCEL_DETAILS_OWNER, PARCEL_DETAILS_GROUP]);
    list heredata = llGetParcelDetails(llGetPos(), [PARCEL_DETAILS_OWNER, PARCEL_DETAILS_GROUP]);
    integer thereflags = llGetParcelFlags(pos);         // flags for dest parcel
    key thereowner = llList2Key(theredata,0);
    key theregroup = llList2Key(theredata,1);
    if ((llList2Key(heredata,0) != thereowner) // dest parcel must have same ownership
    && (llList2Key(heredata,1) != theregroup))
    {   return(FALSE); } // different group and owner at dest parcel
    //  Check for no-script area
    if (thereflags & PARCEL_FLAG_ALLOW_SCRIPTS == 0)            // if scripts off for almost everybody
    {   if (gOwner != thereowner)
        {   if ((thereflags & PARCEL_FLAG_ALLOW_GROUP_SCRIPTS == 0) || (gGroup != theregroup))
            { return(FALSE); }                                  // would die
        }
    }                                // no script area, we would die
    //  Can we enter the destination parcel?
    if (thereflags && PARCEL_FLAG_ALLOW_ALL_OBJECT_ENTRY == 0) 
    {    if (gOwner == thereowner) { return(TRUE); } // same owner, OK
        {   if ((thereflags & PARCEL_FLAG_ALLOW_GROUP_OBJECT_ENTRY) || (gGroup != theregroup))
            { return(FALSE); }
        }
    }
    return(TRUE);  // OK to enter destination parcel
}

start_anim(string anim)
{
    llMessageLinked(LINK_THIS, 1,anim,"");    // tell our AO what we want
}


//  Check if point is directly visible in a straight line.
//  Used when trying to get in front of an avatar.
integer clear_sightline(key id, vector lookatpos)
{   list obstacles = llCastRay(target_pos(id), lookatpos,[]);
    integer status = llList2Integer(obstacles,-1);
    if (status == 0) { return(TRUE); }      // no errors, zero hits, clear sightline.
    pathMsg(PATH_MSG_WARN, "Clear sightline status " + (string)status + " hits: " + (string)obstacles);
    return(FALSE);                          // fails
}
face_dir(vector lookdir)                        // face this way
{
    lookdir = llVecNorm(lookdir);
    vector currentlookdir = <1,0,0>*llGetRot();
    if (currentlookdir * lookdir < 0.95)             // if need to turn to face
    {
        start_anim(STAND_ANIM);
        pathFaceInDirection(lookdir);       // face avatar
        start_anim(IDLE_ANIM);
    }
} 

face_and_greet()                            // turn to face avi
{
    face_dir(vec_to_target(gTarget));                   // turn to face avi
    gGreetedTargets += gTarget;                         
    gAction = ACTION_IDLE;
    llResetTime();              // start attention span timer.
    gDwell = ATTENTION_SPAN;    // wait this long
    llSay(0,"Hello");
}


