//
//  pathexecute.lsl -- component of a path building system
//
//  Part of a system for doing pathfinding in Second Life
//
//  This is where the path components are assembled and keyframe
//  animation lists are created and executed.
//
//  Speed and turning rate are set here, too.
//
//  There is asychrony here. Segments arrive from two sources - 
//  the path planner and the maze solver. Each segment has a 
//  sequence number. From each source, the segments are in
//  ascending order, but the two sources come in asychronously.
//
//  Animats
//  June, 2019
//
//  TODO:
//  1. Handle end of list with a ZERO_VECTOR at the end.
//  2. Report completion via link msg
//  3. Proper status handling.
//  4. Smooth slow to stop at end.
//  5. Prevent rotation and position error accumulation between segs.
//  6. Add ray casting to detect obstacles when moving.
//  7. Add timer handing.
//
#ifndef PATHEXECUTE                                         // include guard, like C/C++
#define PATHEXECUTE
#include "npc/assert.lsl"                                   // assert
#include "npc/mazedefs.lsl"
//
//  Constants
//
//  Error codes. Move to pathdefs.
#define PATHEXEBADPATH1     -2001
#define PATHEXESEGOUTOFSEQ2 -2002
#define PATHEXESEGOUTOFSEQ1 -2003
#define PATHEXEBADSTARTPOS  -2004
//
//  Globals
//                                
float gMaxTurnRate = 0.2;                                   // (radians/sec) max turn rate
float gMaxSpeed = 2.0;                                      // (meters/sec) max speed
integer gPathId = 0;                                        // current path ID
//
//  Segment storage
//  Each segment list is of the form [segmentid, pntcount, pnt, pnt ... segmentid, pntcount, pnt, pnt ...]
//
list gClearSegments = [];                                   // path segment list
list gMazeSegments = [];                                    // maze segment list

list gAllSegments = [];                                     // combined segments from above, points onlyh

//  Segment storage functions. If only we could pass references.
//  ***UNTESTED***
#define pathexeaddseg(lst, segnum, pts) { lst = lst + ([(segnum), llGetListLength(pts)] + (pts); }   // add segment to list

#define pathexegetseg(lst) (llList2List(lst, 2, llList2Integer(lst,2) + 2)) // get first segment from list. Check length first. Expression.

#define pathexedelseg(lst) { lst = llList2List(llList2Integer(lst,2) + 3,-1); } // remove first segment from list. OK on empty list



//
//  pathexeinit -- set up path execute parameters
//
pathexeinit(float speed, float turnrate, float width, float height, float probespacing, integer chartype)
{
    pathexestop();                                          // stop any operation in progress
    gMaxSpeed = speed;
    gMaxTurnRate = turnrate; 
    gPathExeWidth = width;
    gPathExeHeight = height;
    gPathExeProbespacing = probespacing;
    gPathExeChartype = chartype;
    gPathExeNextsegid = 0;   
}


//
//  pathexecutedeliver -- incoming path segment
//
//  Starts motion if necessary
//
//  A new pathid forces a flush of everything.
//
integer pathexedeliver(list pts, integer pathid, integer segmentid, integer ismaze)
{   
    if (llGetListLength(pts) < 2) { return(PATHEXEBADPATH1); } // bogus path
    if (pathid != gPathId)                                  // starting a new segment, kill any movement
    {   if (segmentid != 0) { return(PATHEXESEGOUTOFSEQ1); }// segment out of sequence
        pathexestop();                                      // stop everything
        gPathId = pathid;                                   // reset state to empty
    }
    if (segmentid == 0)                                     // starting a new path
    {   if (gClearSegments != [] || gMazeSegments != []))    // so why do we have segments?
        {   return(PATHEXESEGOUTOFSEQ2); }                  // bad
        vector p0 = llList2Vector(pts,0);                   // get starting point
        if (llVecMag(llGetPos()-p0) > PATHSTARTTOL)         // if too far from current pos
        {   return(PATHEXEBADSTARTPOS); }                   // bad start position
    }  
    if (ismaze)                                             // add to maze or path list
    {   pathexeaddseg(gMazeSegments, segmentid, pts); }
    else
    {   pathexeaddseg(gClearSegments, segmentid, pts); }
    pathexeevent();                                         // advance path processing as needed       
}

//
//  pathexeextrapoints -- add extra points to path on long segments.
//
//  This is to allow smooth speed and direction changes.
//
list pathexeextrapoints(list pts, float distfromend)
{
    list newpts = [];
    integer i;
    integer length = llGetListLength(pts);   
    vector p0 = llList2Vector(pts,0);
    newpts += [p0];                                 // always the initial point     
    for (i=1; i<length; i++)
    {   vector p1 = llList2Vector(pts,i);           // this pt
        //  Do we need to add any intermediate points?
        vector dv = p1-p0;
        vector dir = llVecNorm(dv);
        float dlen = llVecMag(dv);                          
        if (dlen >= 3*distfromend)                  // long enough to need 2 intermediate points
        {   newpts += [p0+dir*distfromend, p1-dir*distfromend]; }
        else if (dlen >= 2*distfromend)
        {   newpts += [(p0+p1)*0.5); }              // add the midpoint 
        newpts += [p1];
        p0 = p1;                                    // for next cycle
    }
    return(newpts);
}

//
//  pathexebuildkfm  -- build keyframe motion list from points
//
list pathexebuildkfm(vector startpos, rotation startrot, list pts)
{
    list kfmdata = [];      // [pos, rot, time ... ]
    integer i;
    integer length = llGetListLength(pts);
    vector pos = startpos;
    vector rot = startrot;
    //  Vectors off the end are ZERO_VECTOR. Code relies on this.
    for (i=1; i<length; i++)                    // skip 1, we are already there.
    {   vector pprev = llList2Vector(pts,i-1);  // previous point
        vector p0 = llList2Vector(pts,i);       // point we are going to
        vector p1 = llList2Vector(pts,i+1);
        kfmdata += pathexecalckfm(pos, rot, pprev, p0, p1);
        pos += llList2Rotatation(kfmdata,-3);   // update pos in world coords
        rot *= llList2Rotation(kfmdata,-2);     // update rot in world coords      
        pprev = p0;
    }
    return(kfmdata);                            // list ready for KFM
}

//
//  pathexecalckfm -- calc the keyframe parameters for one point
//
//  ***NEED TO PREVENT ROTATION ERROR ACCUMULATION***
//
list pathexecakckfm(vector pos, rotation rot, vector pprev, vector p0, vector p1)
{
    vector rp = p0 - pos;                       // p0 in relative coords - advances us to p0
    //  Rotation is to the average direction of the previous and next sections in the XY plane.
    vector invec = pprev-p0;                    // incoming direction
    vector outvec = p1-p0;                      // outgoing direction
    float outveclen = llVecMag(outvec);         // distance of this move
    vector invecnorm = llVecNorm(<invec.x, invec.y, 0>);
    vector outvecnorm = llVecNorm(<outvec.x,outvec.y,0>);
    if (p1 == ZERO_VECTOR) { outvecnorm = invecnorm; } // last section, no turn
    vector dir = llVecNorm(invecnorm+outvecnorm);// next direction
    rotation rr = llRotBetween(invecnorm, dir); // relative rotation
    //  Time computation. Speed is limited by rotation rate.
    float angle = llFAbs(llAngleBetween(ZERO_ROTATION, rr));    // how much rotation is this?
    float rsecs = angle / gMaxTurnRate;         // minimum time for this move per rotation limit
    float rt = outveclen / gMaxSpeed;           // minimum time for this move per speed limit
    if (rsecs > rt) { rt = rsecs; }             // choose longer time
    return([rp, rr, rt]);                       // [rel pos, rel rot, rel time]
} 

//
//  pathexegetsegment -- get next segment from either queue.
//
//  Must be segment segid.
//
list pathexegetsegment(integer segid)
{
    //  Try path segment queue
    if ((llGetListLength(gClearSegments) > 0) && llList2Integer(gClearSegments,0) == segid)
    {   list nextseg = pathexegetseg(gClearSegments); pathexedelseg(gClearSegments); return(nextseg); }
    //  Try maze segment queue
    if ((llGetListLength(gMazeSegments) > 0) && llList2Integer(gMazeSegments,0) == segid)
    {   list nextseg = pathexegetseg(gMazeSegments); pathexedelseg(gMazeSegments); return(nextseg); }
    return([]); 
}
//
//  pathexeassemblesegs  -- combine segments into one big list.
//
pathexeassemblesegs()
{   while (TRUE)
    {   list nextseg = pathexegetsegment(gPathExeNextsegid);   // get next segment if any
        if (nextseg == []) return;                      // nothing to do
        gPathExeNextsegid++;                                   // advance seg ID
        if (gAllSegments == [])
        {   gAllSegments = nextseg;                     // first segment
            nextseg = [];
        } else {
            vector lastpt = llList2Vector(gAllSegments,-1);
            vector firstpt = llList2Vector(gAllSegments,0);
            assert(llVecMag(lastpt-firstpt) < 0.01);    // endpoints should match
            nextseg = llList2List(nextseg,1,-1);        // discard new duplicate point
            //  If we can take a short-cut at the join between two segments, do so.
            if (obstaclecheckpath(llList2Vector(gAllSegments,-2), llList2Vector(nextseg,0), gPathExeWidth, gPathExeHeight, gPathExeProbespacing, gPathExeChartype))
            {   gAllSegments = llList2List(gAllSegments,0,-2) + pathextrapoints(nextseg, gPathExeDisttoend); }
            else
            {   gAllSegments += pathextrapoints(nextseg, gPathExeDisttoend);                // no, can't drop point
            }
        }
    }
}
//
//  pathexedomove -- feed in next section if any
//
pathexedomove()
{
    if (gPathExeMoving) { return; }                     // we are moving, do nothing
    pathassemblesegs();                                 // have work to do?
    if (gAllSegments != [])                             // if work
    {   list kfmmoves = pathexebuildkfm(llGetPos(), llGetRot(), gAllSegments);   // build list of commands to do
        DEBUGPRINT1("KFM: " + llDumpList2String(kfmmoves,","));  // dump the commands
        llSetKeyframedMotion(kfmmoves, []);             // begin motion
        gPathExeMoving = TRUE;                          // movement in progress
    } else {
        //  ***NEED TO DETECT END OF SEGMENTS***
        DEBUGPRINT1("Waiting for maze solver to catch up.");    // solver running behind action
    }
}

//
//  pathexemovementend -- movement has finished, feed in next section if any
//
pathexemovementend()
{   gPathExeMoving = FALSE;                                 // not moving
    pathexedomove();
}

//
//  pathexetimer  -- timer event, check progress
//
pathexetimer()
{
}

//
//  pathexestop -- trouble, stop and abort keyframe motion
//
pathexestop(integer status)
{
    llSetKeyframedMotion([],[KFM_COMMAND, KFM_CMD_STOP);    // stop whatever is going on
    gClearSegments = [];                                    // reset state
    gMazeSegments = [];
    gAllSegments = [];
    gPathExeNextsegid = 0; 
    gPathExeMoving = FALSE;                                 // not moving     

}

#endif // PATHEXECUTE
