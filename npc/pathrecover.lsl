//
//  pathrecover.lsl -- component of a path building system
//
//  Part of a system for doing pathfinding in Second Life
//
//  Gets the NPC back to a safe position.
//
//  Communicates with pathmove.lsl, which got too big.
//
//  Animats
//  October, 2019
//
//  License: GPLv3
//
///
#include "npc/assert.lsl"                                   // assert
#include "npc/patherrors.lsl"
#include "npc/pathmazedefs.lsl"
#include "npc/pathbuildutils.lsl"
#include "npc/pathmovecall.lsl"
//
//  Constants
//

//
//  Globals
//
integer gPathrecoverId = 0;                                    // current path ID

//
//  pathcheckforwalkable  -- is there a walkable below here?
//
//  Returns 0 or error status
//
//
integer pathcheckforwalkable()
{   vector pos = llGetPos();                                // we are here
    vector fullheight = <0,0,gPathMoveHeight>;              // add this for casts from middle of character
    vector halfheight = fullheight*0.5;
    vector p = pos-halfheight;                              // position on ground
    vector mazedepthmargin = <0,0,MAZEBELOWGNDTOL>;         // subtract this for bottom end of ray cast
    if (obstacleraycastvert(p+fullheight,p-mazedepthmargin) >= 0)  
    {   return(0); }                                        // no problem   
    //  Trouble, there is no walkable here
    return(PATHERRWALKABLEFAIL);                            // fail for now, may recover later
}

//
//  findnearbyopenpos -- find a nearby open position for recovery purposes.
//
//  Returns ZERO_VECTOR if no find.
//  Returned position is at ground level.
//
vector findnearbyopenpos()
{   vector pos = llGetPos();                                // we are here, halfheight level position
    vector groundpos = pos - <0,0,gPathHeight*0.5>;         // ground level position
    integer i;
    integer TRYPOINTS = 8;                                  // number of points to try                                
    for (i=0; i<TRYPOINTS; i++)                             // circular search pattern
    {   float ang = (i*(PI*2))/TRYPOINTS;                   // angle
        vector offset = <llCos(ang),llSin(ang),0>*(gPathWidth); // one character width in a circle around the character
        vector trypos = groundpos+offset;
        float z = pathcheckcelloccupied(groundpos,trypos, TRUE, FALSE); // is this space clear?
        if (z > 0)                                          // yes, clear here
        {   trypos.z = z;                                   // use Z from cell occupy check, which is ground level
            pathMsg(PATH_MSG_WARN,"Recovering to nearby point " + (string)trypos);
            return(trypos);                                 // success
        }
    }
    return(ZERO_VECTOR);                                    // no find                    
}
//
//  findrecoveropenpos -- find an open position in the recovery point list.
//
//  Returns ZERO_VECTOR if no find.
//  Returned position is at ground level.
//
vector findrecoveropenpos(list pts)
{   vector pos = llGetPos();                                // we are here, halfheight level position
    //  Trouble, there is no walkable here
    //  Attempt recovery. Try to find a previous good location that's currently open and move there.
    integer i = llGetListLength(pts);                       // for stored good points, most recent first
    while (i-- > 1)                                         // for newest (len-1) to oldest (0)
    {   vector recoverpos = llList2Vector(pts,i);           // try to recover to here - ground level position
        vector prevrecoverpos = llList2Vector(pts,i-1);
        vector halfheight = <0,0,gPathHeight*0.5>;
        if (pathcheckcelloccupied(prevrecoverpos, recoverpos, TRUE, FALSE) >= 0.0) // if clear to go there
        {   return(recoverpos);
        }
    }
    return(ZERO_VECTOR);
}
//
//  diagnoserecoverymove -- report on recovery move soundness
//
//  If the recovery move goes through something, this is logged.
//  But it doesn't do more than that. 
//  It's an undesirable event, but tolerable if very rare.
//
//  recoverpos is at ground height
//
diagnoserecoverymove(vector recoverpos)
{   vector pos = llGetPos();                                    // pos, mid-height
    //  Debug check - if recovery goes through something, what is it? 
    vector halfheight = <0,0,gPathHeight*0.5>;                  // up by half the height from the ground
    vector dv = recoverpos+halfheight-pos;                      // vector to recovery point
    if (llVecMag(dv) < gPathWidth + 0.01) { return; }           // if very small move, do not make flythrough check.
    vector startcast = pos + llVecNorm(dv)*gPathWidth;          // start cast 1 width away from self to avoid reporting collision as flythrough
    list castresult = castray(startcast,recoverpos+halfheight,PATHCASTRAYOPTSOBS);  // Horizontal cast at full height, any hit is bad
    float result = pathcastfoundproblem(castresult, FALSE, FALSE);     // if any hits at all, other than self, fail
    if (result != INFINITY)                                     // if something there
     {  integer status = llList2Integer(castresult,-1); // ray cast status
        integer j;
        for (j=0; j<3*status; j+=3)                             // strided list search
        {   key hitobj = llList2Key(castresult, j+0);           // get name of object hit by raycast
            vector hitpos = llList2Vector(castresult,j+1);      // where hit
            string hitname;
            if (hitobj != gPathSelfObject)                      // if hit something other than self
            {   if (hitobj == NULL_KEY)                         // null key is ground
                {   hitname = "Ground"; }
                else                                            // other object
                {   hitname = llKey2Name(hitobj);               // name of object
                    hitname += " " + (string)llList2Vector(llGetObjectDetails(hitobj,[OBJECT_POS]),0); // position of hit object
                }                      
            }
            pathMsg(PATH_MSG_WARN,"Recovery move hit " + hitname + " at " + (string)hitpos);
        }
        pathMsg(PATH_MSG_ERROR,"Recovery move goes through objects between " + (string)startcast + " and " + (string)(recoverpos+halfheight));
    }
}
//
//  pathrecoverwalkable  -- get back onto walkable surface if possible
//
//  Returns 0 or error status
//
integer pathrecoverwalkable(list pts)
{   vector pos = llGetPos();                        // we are here, halfheight level position
    //  Trouble, there is no walkable here
    //  Attempt recovery. Try to find a previous good location that's currently open and move there.
    pathMsg(PATH_MSG_WARN,"No walkable below after move to " + (string)pos + ". Recovery points available: " + (string)llGetListLength(pts));
    vector recoverpos = findnearbyopenpos();        // try a nearby point. Recoverpos is at ground height
    if (recoverpos == ZERO_VECTOR)                  // that didn't work
    {   recoverpos = findrecoveropenpos(pts);       // try all recovery points
    }
    if (recoverpos == ZERO_VECTOR)                  // nothing worked, tell owner
    {   pathMsg(PATH_MSG_ERROR,"Unable to recover from lack of walkable below " + (string)pos + " by recovering to any of " + llDumpList2String(pts,",")); 
        return(PATHERRWALKABLEFAIL);                // we're probably stuck now
    }
    //  We have a valid recovery point.      
    pathMsg(PATH_MSG_WARN,"Recovering by move to " + (string) recoverpos);
    diagnoserecoverymove(recoverpos);               // error loggin only
    //  We do the move as a phantom, to avoid pushing things around.
    vector halfheight = <0,0,gPathHeight*0.5>;      // up by half the height from the ground
    llSleep(0.5);                                   // allow time for stop to take effect
    llSetPrimitiveParams([PRIM_PHANTOM, TRUE]);     // set to phantom for forced move to avoid collisions
    llSetPos(recoverpos + halfheight);              // forced move to previous good position
    llSleep(0.5);                                   // give time to settle
    llSetPrimitiveParams([PRIM_PHANTOM, FALSE]);    // back to normal solidity
    return(PATHERRWALKABLEFIXED);
}
#ifdef OBSOLETE
//
//  pathrecoverwalkable  -- get back onto walkable surface if possible
//
//  Returns 0 or error status
//
integer pathrecoverwalkable(list pts)
{   vector pos = llGetPos();                                // we are here, halfheight level position
    //  Trouble, there is no walkable here
    //  Attempt recovery. Try to find a previous good location that's currently open and move there.
    integer i = llGetListLength(pts);                       // for stored good points, most recent first
    pathMsg(PATH_MSG_WARN,"No walkable below after move to " + (string)pos + ". Recovery points available: " + (string)i);
    while (i-- > 1)                                         // for newest (len-1) to oldest (0)
    {   vector recoverpos = llList2Vector(pts,i);           // try to recover to here - ground level position
        vector prevrecoverpos = llList2Vector(pts,i-1);
        vector halfheight = <0,0,gPathHeight*0.5>;
        if (pathcheckcelloccupied(prevrecoverpos, recoverpos, TRUE, FALSE) >= 0.0) // if clear to go there
        {   pathMsg(PATH_MSG_WARN,"Recovering by move to " + (string) recoverpos);
            //  Debug check - if recovery goes through something, what is it? 
            vector dv = recoverpos+halfheight-pos;          // vector to recovery point
            vector startcast = pos + llVecNorm(dv)*gPathWidth; // start cast 1 width away from self to avoid reporting collision as flythrough
            list castresult = castray(startcast,recoverpos+halfheight,PATHCASTRAYOPTSOBS);  // Horizontal cast at full height, any hit is bad
            float result = pathcastfoundproblem(castresult, FALSE, FALSE);     // if any hits at all, other than self, fail
            if (result != INFINITY)                                     // if something there
            {   integer status = llList2Integer(castresult,-1); // ray cast status
                integer j;
                for (j=0; j<3*status; j+=3)                             // strided list search
                {   key hitobj = llList2Key(castresult, j+0);           // get name of object hit by raycast
                    vector hitpos = llList2Vector(castresult,j+1);      // where hit
                    string hitname;
                    if (hitobj != gPathSelfObject)                      // if hit something other than self
                    {   if (hitobj == NULL_KEY)                         // null key is ground
                        {   hitname = "Ground"; }
                        else                                            // other object
                        {   hitname = llKey2Name(hitobj);               // name of object
                            hitname += " " + (string)llList2Vector(llGetObjectDetails(hitobj,[OBJECT_POS]),0); // position of hit object
                        }                      
                    }
                    pathMsg(PATH_MSG_WARN,"Recovery move hit " + hitname + " at " + (string)hitpos);
                }
                pathMsg(PATH_MSG_ERROR,"Recovery move goes through objects between " + (string)startcast + " and " + (string)(recoverpos+halfheight));
            }
            //  We do the move as a phantom, to avoid pushing things around.
            llSleep(0.5);                                   // allow time for stop to take effect
            llSetPrimitiveParams([PRIM_PHANTOM, TRUE]);     // set to phantom for forced move to avoid collisions
            llSetPos(recoverpos + halfheight);              // forced move to previous good position
            llSleep(0.5);                                   // give time to settle
            llSetPrimitiveParams([PRIM_PHANTOM, FALSE]);    // back to normal solidity
            return(PATHERRWALKABLEFIXED);
        }
    }
    pathMsg(PATH_MSG_ERROR,"Unable to recover from lack of walkable below " + (string)pos + " by recovering to any of " + llDumpList2String(pts,",")); 
    return(PATHERRWALKABLEFAIL);
}
#endif // OBSOLETE


//
//  pathrecoverrequest  -- JSON from path move
//
//  We get a list of possible recovery points.
//
pathrecoverrequest(string jsn, key hitobj) 
{   pathMsg(PATH_MSG_WARN,"Path recover request: " + jsn);
    string requesttype = llJsonGetValue(jsn,["request"]);   // request type  
    if (requesttype == "recover")                    // recover to known good position, requested by pathprep
    {   //  Go back to some previous good point.
        integer pathid = (integer)llJsonGetValue(jsn, ["pathid"]);
        list ptsstr = llJson2List(llJsonGetValue(jsn, ["recoverpoints"])); // points, as list of strings
        list pts = [];                                  // points as list of vectors
        integer i;
        for (i=0; i<llGetListLength(ptsstr); i++) { pts += (vector)llList2String(ptsstr,i); } // convert JSON strings to LSL vectors
        jsn = "";                                       // release memory
        integer status = pathrecoverwalkable(pts);      // force to a walkable position
        pathrecoverreply(pathid, status, hitobj);
        ////pathdonereply(status, hitobj, pathid);          // report move completion
    } else {
        pathMsg(PATH_MSG_ERROR,"Bad msg: " + jsn);
    }
}

//
//  The main program of the recover task.
//
default
{
    state_entry()
    {   pathinitutils();                                        // init library
    }


    link_message(integer status, integer num, string jsn, key id )
    {   if (num == LINKMSGRECOVERREQUEST)               // recovery request
        {   pathrecoverrequest(jsn,id); 
        } else if (num == PATHPARAMSINIT)
        {   pathinitparams(jsn);                        // initialize params
        } else if (num == DEBUG_MSGLEV_BROADCAST)               // set debug message level for this task
        {   debugMsgLevelSet(jsn);
        }

    }
    
}
