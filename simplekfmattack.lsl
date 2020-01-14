//
//
//  simplekfmattack.lsl -- simple movement for an animesh character.
//
//  Start when rezzed, move N meters forward, run attack anim, repeat.
//
//  Stops and attacks if an obstacle in front of it.
//  Stops and stands at parcel boundary.
//  
//
//  Animats
//  January, 2020
//
//  License: GPLv3
//
//
//  Configuration
//
float MOVEDIST = 4.0;                                       // (m) distance to move between threats
float MOVESPEED = 3.0;                                      // (m/sec) speed of movement
float ATTACKTIME = 4.0;                                     // (sec) time for attack
float LOOKDIST = 2.0;                                       // (m) distance to look ahead for threat
string RUNANIM = "run";                                     // (anim name) anim for running
string STANDANIM = "stand";                                 // (anim name) anim for standing
string ATTACKANIM = "jump";                                 // (anim name) anim for attacking

//  State constants
//
integer STATE_STAND = 0;                                    // starting up
integer STATE_RUN = 1;                                      // running
integer STATE_THREATEN = 2;                                 // threatening attack
integer STATE_ATTACK = 3;                                   // attacking something in front
integer STATE_DONE = 4;                                     // done



//
//  Globals
//
integer gState = STATE_STAND;                               // state of state machine
key gParcelid;                                              // parcel ID at start
//
//  getparcelid -- get parcel ID of parcel at pos
//
key getparcelid(vector pos)
{   return(llList2Key(llGetParcelDetails(pos, [PARCEL_DETAILS_ID]),0)); }

//
//  domove -- move in current direction
//
domove(float distance, float speed)
{   list kfmmove = [<distance,0,0>,ZERO_ROTATION,speed/distance];
    llStopObjectAnimation(STANDANIM);
    llStopObjectAnimation(ATTACKANIM);        
    llStartObjectAnimation(RUNANIM); 
    llSetKeyframedMotion(kfmmove, [KFM_MODE, KFM_FORWARD]);     // begin motion
    gState = STATE_RUN;                                         // run state 
    llSetTimerEvent(0.2);                                       // speed for cast ray polls                    
}

//
//  doattack -- attack in current direction
//
doattack(integer nextstate)
{
    llStopObjectAnimation(STANDANIM);
    llStopObjectAnimation(RUNANIM); 
    llStartObjectAnimation(ATTACKANIM);
    gState = nextstate;
    llSetTimerEvent(ATTACKTIME);                                // attack for this long
}
//
//  dostand -- just stand at start
//
dostand()
{
    llStopObjectAnimation(ATTACKANIM);
    llStopObjectAnimation(RUNANIM); 
    llStartObjectAnimation(STANDANIM);
    gState = STATE_STAND;
    llSetTimerEvent(2.0);                                       // allow rez to complete before moving
}
//
//  dodone -- all done
//
dodone()
{
    llStopObjectAnimation(ATTACKANIM);
    llStopObjectAnimation(RUNANIM); 
    llStartObjectAnimation(STANDANIM);
    gState = STATE_DONE;
    llSetTimerEvent(0.0);                                       // nothing ever happens again
}
//
//  getroot -- get root prim from ID
//
key getroot(key id)
{   return(llList2Key(llGetObjectDetails((id),[OBJECT_ROOT]),0)); } 
//
//  castray -- do ray cast, ignoring self.
//
//  We can get a hit from our own object when the root is outside the object. 
//
float castray(vector frompt, vector topt)
{
    list castresult = llCastRay(frompt, topt, [RC_MAX_HITS,3,RC_DATA_FLAGS,RC_GET_ROOT_KEY]);   // look for obstacle ahead
    llOwnerSay("Cast result at " + (string) frompt + ": " + llDumpList2String(castresult,","));     // ***TEMP***
    integer status = llList2Integer(castresult,-1);             // status is at end
    if (status < 0) { return(-1); }                             // fails
    integer i;
    for (i=0; i<status*2; i+= 2)                                // examine all hits
    {   key id = llList2Key(castresult,i);                      // key of thing seen
        vector targetpos = llList2Vector(castresult,i+1);       // object seen
        if (getroot(id) != getroot(llGetKey()))                 // if not self
        {   return(llVecMag(targetpos-frompt));                 // dist to target
        }
    }
    return(99999999.0);                                         // no target in range
}
//
//  dotimer -- do timer event
//
//  A simple state machine
//
dotimer()
{   llOwnerSay("Timer state: " + (string)gState);               // ***TEMP***
    if (gState == STATE_RUN)                                    // if running
    {   //  Cast ray to see if obstacle detected
        vector pos = llGetRootPosition();
        rotation rot = llGetRootRotation();
        vector aheadpt = pos + <LOOKDIST,0,0>*rot;              // other end of ray cast
        if (getparcelid(aheadpt) != gParcelid)                  // if going off parcel
        {   dodone();                                           // we are done
            llOwnerSay("Edge of parcel");                       // ***TEMP***
            return;
        }                        
        float dist = castray(pos,aheadpt);                      // look ahead for an obstacle
        if (dist <= LOOKDIST)                                   // target detected
        {   doattack(STATE_DONE);                               // attack it and stop
            return;
        }
        return;
    } else if (gState == STATE_ATTACK)                          // attacking and time has expired
    {   domove(MOVEDIST, MOVESPEED);                            // back to running
    } else if (gState == STATE_THREATEN)                        // threaten and done doing that
    {   domove(MOVEDIST, MOVESPEED);        
    } else if (gState == STATE_STAND)                           // initial stand
    {   domove(MOVEDIST, MOVESPEED);                            // get going
    } else if (gState == STATE_DONE)
    {   dodone();
    }           
}

//
//  domoveend -- movement has completed
//
domoveend()
{   if (gState == STATE_RUN)                                   // if was moving
    {   doattack(STATE_THREATEN);                               // do threaten attack
    }
}

//
//  The main program of the move task.
//
default
{
    state_entry()
    {   gParcelid = getparcelid(llGetRootPosition()); // starting parcel ID
        dostand();                              // get started
    }

    on_rez(integer rezparam) 
    {   llResetScript(); }
    
    timer()
    {   dotimer();
    }
    
    moving_end()
    {   domoveend(); }   
    
}
