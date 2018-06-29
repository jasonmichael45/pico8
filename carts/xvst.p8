pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- xwing vs. tie figther
-- by freds72

-- game globals
local time_t=0
local good_side,bad_side,any_side,no_side=0x1,0x2,0x0,0x3

-- register json context here
local _tok={
 ['true']=true,
 ['false']=false}
function nop() return true end
local _g={
	good_side=good_side,
	bad_side=bad_side,
	any_side=any_side,
	nop=nop}

-- json parser
-- from: https://gist.github.com/tylerneylon/59f4bcf316be525b30ab
local table_delims={['{']="}",['[']="]"}
local function match(s,tokens)
	for i=1,#tokens do
		if(s==sub(tokens,i,i)) return true
	end
	return false
end
local function skip_delim(str, pos, delim, err_if_missing)
 if sub(str,pos,pos)!=delim then
  if(err_if_missing) assert'delimiter missing'
  return pos,false
 end
 return pos+1,true
end
local function parse_str_val(str, pos, val)
	val=val or ''
	if pos>#str then
		assert'end of input found while parsing string.'
	end
	local c=sub(str,pos,pos)
	if(c=='"') return _g[val] or val,pos+1
	return parse_str_val(str,pos+1,val..c)
end
local function parse_num_val(str,pos,val)
	val=val or ''
	if pos>#str then
		assert'end of input found while parsing string.'
	end
	local c=sub(str,pos,pos)
	-- support base 10, 16 and 2 numbers
	if(not match(c,"-xb0123456789abcdef.")) return tonum(val),pos
	return parse_num_val(str,pos+1,val..c)
end
-- public values and functions.

function json_parse(str, pos, end_delim)
	pos=pos or 1
	if(pos>#str) assert'reached unexpected end of input.'
	local first=sub(str,pos,pos)
	if match(first,"{[") then
		local obj,key,delim_found={},true,true
		pos+=1
		while true do
			key,pos=json_parse(str, pos, table_delims[first])
			if(key==nil) return obj,pos
			if not delim_found then assert'comma missing between table items.' end
			if first=="{" then
				pos=skip_delim(str,pos,':',true)  -- true -> error if missing.
				obj[key],pos=json_parse(str,pos)
			else
				add(obj,key)
			end
			pos,delim_found=skip_delim(str, pos, ',')
	end
	elseif first=='"' then
		-- parse a string (or a reference to a global object)
		return parse_str_val(str,pos+1)
	elseif match(first,"-0123456789") then
		-- parse a number.
		return parse_num_val(str, pos)
	elseif first==end_delim then  -- end of an object or array.
		return nil,pos+1
	else  -- parse true, false
		for lit_str,lit_val in pairs(_tok) do
			local lit_end=pos+#lit_str-1
			if sub(str,pos,lit_end)==lit_str then return lit_val,lit_end+1 end
		end
		assert'invalid json token'
	end
end

-- false: chase
-- true: cockpit
local cockpit_view,cam=false
-- player
local plyr_playing,score,invert_y,plyr=false,0,1
local actors,ground_actors,parts,all_parts={},{},{}
-- ground constants 
local ground_scale,ground_colors,ground_level=4,json_parse'[1,13,6]'

-- screen management
local start_screen,game_screen,gameover_screen,cur_screen={},{},{}

-- camera shake
local shkx,shky=0,0
function screen_shake(pow)
	shkx,shky=min(4,shkx+rnd(pow)),min(4,shky+rnd(pow))
end
function screen_update()
	shkx*=-0.7-rnd(0.2)
	shky*=-0.7-rnd(0.2)
	if abs(shkx)<0.5 and abs(shky)<0.5 then
		shkx,shky=0,0
	end
	camera(shkx,shky)
end
-- volumetric sound
local all_vol=json_parse'[0x700.0700,0x600.0600,0x500.0500,0x400.0400,0x300.0300,0x200.0200,0x100.0100,0x100.0100]'
function sfx_v(s,pos)
	local d=sqr_dist(cam.pos,pos)
	-- set volume
	-- todo: move sqrt into volume array
	local vol=all_vol[mid(flr(sqrt(d)/8+0.5),1,#all_vol)]
	local src,dst=0x3200+68*s,0x3200+68*63
	-- 2 notes/loop (eg 4 bytes)
	-- 32 notes total
	for k=1,16 do
		 -- copy sound + adjust volume
		local pair=bor(band(peek4(src),0xf1ff.f1ff),vol)
		poke4(dst,pair)
		src+=4
		dst+=4
	end
	-- misc sfx attributes
	poke4(dst,peek4(src))
	-- play
	sfx(63)
end

-- zbuffer (kind of)
local drawables={}
function zbuf_clear()
	drawables={}
end
function zbuf_draw()
	local objs={}
	for _,d in pairs(drawables) do
		local p=d.pos
		local x,y,z,w=cam:project(p[1],p[2],p[3])
		if z>0 then
			add(objs,{obj=d,key=z,x=x,y=y,z=z,w=w})
		end
	end
	-- z-sorting
	sort(objs)
	-- actual draw
	for i=1,#objs do
		local d=objs[i]
		d.obj:draw(d.x,d.y,d.z,d.w)
	end
end

function zbuf_filter(array)
	for _,a in pairs(array) do
		if not a:update() then
			del(array,a)
		else
			add(drawables,a)
		end
	end
end

function clone(src,dst)
	-- safety checks
	if(src==dst) assert()
	if(type(src)!="table") assert()
	dst=dst or {}
	for k,v in pairs(src) do
		if(not dst[k]) dst[k]=v
	end
	-- randomize selected values
	if src.rnd then
		for k,v in pairs(src.rnd) do
			-- don't overwrite values
			if not dst[k] then
				dst[k]=v[3] and rndarray(v) or rndlerp(v[1],v[2])
			end
		end
	end
	return dst
end

function lerp(a,b,t)
	return a*(1-t)+b*t
end
function rndlerp(a,b)
	return lerp(b,a,1-rnd())
end
function smoothstep(t)
	t=mid(t,0,1)
	return t*t*(3-2*t)
end
function rndrng(ab)
	return flr(rndlerp(ab[1],ab[2]))
end
function rndarray(a)
	return a[flr(rnd(#a))+1]
end

-- https://github.com/morgan3d/misc/tree/master/p8sort
function sort(data)
 for num_sorted=1,#data-1 do 
  local new_val=data[num_sorted+1]
  local new_val_key,i=new_val.key,num_sorted+1

  while i>1 and new_val_key>data[i-1].key do
   data[i]=data[i-1]   
   i-=1
  end
  data[i]=new_val
 end
end

function sqr_dist(a,b)
	local dx,dy,dz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
	-- avoid overflow
	if abs(dx)>128 or abs(dy)>128 or abs(dz)>128 then
		return 32000
	end

	return dx*dx+dy*dy+dz*dz
end

function make_rnd_v(scale)
	local v={rnd()-0.5,rnd()-0.5,rnd()-0.5}
	v_normz(v)
	v_scale(v,scale)
	return v
end

function make_rnd_pos_v(a,rng)
	local p=make_rnd_v(8)
	p[3]+=rng
	local d,v=0
	while d==0 do
		v=make_rnd_v(4)
		v_add(v,p,-1)
		d=v_normz(v)
	end
	m_x_v(a.m,p)
	return p,v
end

function make_v_cross(a,b)
	local ax,ay,az=a[1],a[2],a[3]
	local bx,by,bz=b[1],b[2],b[3]
	return {ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx}
end
-- world axis
local v_fwd,v_right,v_up={0,0,1},{1,0,0},{0,1,0}

function v_clone(v)
	return {v[1],v[2],v[3]}
end
function v_lerp(a,b,t)
	return {
		lerp(a[1],b[1],t),
		lerp(a[2],b[2],t),
		lerp(a[3],b[3],t)}
end
function v_dot(a,b)
	return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
end
function v_normz(v)
	local d=v_dot(v,v)
	if d>0 then
		d=sqrt(d)
		v[1]/=d
		v[2]/=d
		v[3]/=d
	end
	return d
end
function v_clamp(v,l)
	local d=v_dot(v,v)
	if d>l*l then
		v_scale(v,l/sqrt(d))
	end
end
function v_scale(v,scale)
	v[1]*=scale
	v[2]*=scale
	v[3]*=scale
end
function v_add(v,dv,scale)
	scale=scale or 1
	v[1]+=scale*dv[1]
	v[2]+=scale*dv[2]
	v[3]+=scale*dv[3]
end
function in_cone(p,t,fwd,angle,rng)
	local v=v_clone(t)
	v_add(v,p,-1)
	-- close enough?
	if sqr_dist(v,v)<rng*rng then
		v_normz(v)
		-- in cone?
		return v_dot(fwd,v)>angle
	end
	return false
end

-- matrix functions
function m_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	v[1],v[2],v[3]=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
end
-- 3x3 matrix mul (orientation only)
function o_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	v[1],v[2],v[3]=m[1]*x+m[5]*y+m[9]*z,m[2]*x+m[6]*y+m[10]*z,m[3]*x+m[7]*y+m[11]*z
end
function m_x_xyz(m,x,y,z)
	return {
		m[1]*x+m[5]*y+m[9]*z+m[13],
		m[2]*x+m[6]*y+m[10]*z+m[14],
		m[3]*x+m[7]*y+m[11]*z+m[15]}
end
function make_m(x,y,z)
	local m={}
	for i=1,16 do
		m[i]=0
	end
	m[1],m[6],m[11],m[16]=1,1,1,1
	m[13],m[14],m[15]=x or 0,y or 0,z or 0
	return m
end

function make_m_toward(z,up)
 local x=make_v_cross(up,z)
	-- aligned?
	if v_dot(x,x)<0.0001 then
		-- up and z //
		if abs(up[3])>0.99 then
			z[1]+=0.01
		else
			z[3]+=0.01
		end
		v_normz(z)
		x=make_v_cross(up,z)
	end
		
	v_normz(x)
	local y=make_v_cross(z,x)
	v_normz(y)
 
	return { 
		x[1],x[2],x[3],0,
		y[1],y[2],y[3],0,
  z[1],z[2],z[3],0,
		0,0,0,1}
end
-- quaternion
function make_q(v,angle)
	angle/=2
	-- fix pico sin
	local s=-sin(angle)
	return {v[1]*s,
	        v[2]*s,
	        v[3]*s,
	        cos(angle)}
end
function q_clone(q)
	return {q[1],q[2],q[3],q[4]}
end
function q_x_q(a,b)
	local qax,qay,qaz,qaw=a[1],a[2],a[3],a[4]
	local qbx,qby,qbz,qbw=b[1],b[2],b[3],b[4]
        
	a[1]=qax*qbw+qaw*qbx+qay*qbz-qaz*qby
	a[2]=qay*qbw+qaw*qby+qaz*qbx-qax*qbz
	a[3]=qaz*qbw+qaw*qbz+qax*qby-qay*qbx
	a[4]=qaw*qbw-qax*qbx-qay*qby-qaz*qbz
end
function m_from_q(q)
	local x,y,z,w=q[1],q[2],q[3],q[4]
	local x2,y2,z2=x+x,y+y,z+z
	local xx,xy,xz=x*x2,x*y2,x*z2
	local yy,yz,zz=y*y2,y*z2,z*z2
	local wx,wy,wz=w*x2,w*y2,w*z2

	return {
		1-(yy+zz),xy+wz,xz-wy,0,
		xy-wz,1-(xx+zz),yz+wx,0,
		xz+wy,yz-wx,1-(xx+yy),0,
		0,0,0,1
	}
end

-- only invert 3x3 part
function m_inv(m)
	m[2],m[5]=m[5],m[2]
	m[3],m[9]=m[9],m[3]
	m[7],m[10]=m[10],m[7]
end
-- inline matrix invert
-- inc. position
function m_inv_x_v(m,v)
	local x,y,z=v[1]-m[13],v[2]-m[14],v[3]-m[15]
	v[1],v[2],v[3]=m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z
end
function m_set_pos(m,v)
	m[13],m[14],m[15]=v[1],v[2],v[3]
end
-- returns foward vector from matrix
function m_fwd(m)
	return {m[9],m[10],m[11]}
end
-- returns up vector from matrix
function m_up(m)
	return {m[5],m[6],m[7]}
end

-- models
local all_models=json_parse'{"logo":{"c":10},"deathstar":{"c":3},"trench1":{"c":13},"turret":{"c":8,"r":1.1,"wp":{"sfx":1,"part":"ground_laser","dmg":1,"dly":24,"pos":[[-0.2,0.8,0.65],[0.2,0.8,0.65]],"n":[[0,0,1],[0,0,1]]}},"xwing":{"c":7,"r":0.8,"engine_part":"purple_trail","engines":[[-0.57,0.44,-1.61],[-0.57,-0.44,-1.61],[0.57,0.44,-1.61],[0.57,-0.44,-1.61]],"proton_wp":{"dmg":4,"part":"proton","sfx":6,"dly":60,"pos":[0,-0.4,1.5],"n":[0,0,1]},"wp":{"sfx":2,"dmg":1,"dly":8,"pos":[[2.1,0.6,1.6],[2.1,-0.6,1.6],[-2.1,-0.6,1.6],[-2.1,0.6,1.6]],"n":[[-0.0452,-0.0129,0.9989],[-0.0452,0.0129,0.9989],[0.0452,0.0129,0.9989],[0.0452,-0.0129,0.9989]]}},"tie":{"c":5,"r":1.2,"engine_part":"blue_trail","engines":[[0,0,-0.5]],"wp":{"sfx":8,"dmg":1,"dly":24,"pos":[[0.7,-0.7,0.7],[-0.7,-0.7,0.7]],"n":[[0,0,1],[0,0,1]]}},"tiex1":{"c":13,"r":1.2,"wp":{"sfx":6,"dmg":2,"dly":24,"pos":[[0.7,-0.7,0.7],[-0.7,-0.7,0.7]],"n":[[0,0,1],[0,0,1]]}},"junk2":{"c":3,"r":1.2},"generator":{"c":6,"r":2},"mfalcon":{"c":5,"engine_part":"mfalcon_trail","engines":[[0,0,-5.86]],"wp":{"sfx":1,"dmg":1,"dly":45,"pos":[[0.45,1.1,0],[-0.45,1.1,0],[0.45,-1.3,0],[-0.45,1.3,0]],"n":[[0,0,1],[0,0,1],[0,0,1],[0,0,1]]}},"vent":{"c":5,"r":1},"ywing":{"c":7,"r":1,"wp":{"sfx":1,"dmg":1,"dly":18,"pos":[[0.13,0,3.1],[-0.13,0,3.1]],"n":[[0,0,1],[0,0,1]]}}}'
local dither_pat=json_parse'[0b1111111111111111,0b0111111111111111,0b0111111111011111,0b0101111111011111,0b0101111101011111,0b0101101101011111,0b0101101101011110,0b0101101001011110,0b0101101001011010,0b0001101001011010,0b0001101001001010,0b0000101001001010,0b0000101000001010,0b0000001000001010,0b0000001000001000,0b0000000000000000]'

function draw_actor(self,x,y,z,w)
	--[[
	local s=""	
	local recover=false
	if self.overg_t>=25 then
		s,recover=s.."⧗",true
	end
	if self.target then
		s=s.."☉"
	elseif not self.target then
		s=s.."?"
	end
	s=s.."\n"..self.g.."["..self.overg_t.."]"
	print(s,x-8,y-w-16,recover and 8 or 11)
	]]
	-- distance culling
	if w>1 then
		draw_model(self.model,self.m,x,y,z,w)
	else
		circfill(x,y,1,self.model.c)
	end
	-- if(self.model.r) circ(x,y,self.model.r*w,7)
end

-- unpack models
local mem=0x1000
function unpack_int()
	local i=peek(mem)
	mem+=1
	return i
end
function unpack_float(scale)
	local f=(unpack_int()-128)/32	
	return f*(scale or 1)
end
-- valid chars for model names
local itoa='_0123456789abcdefghijklmnopqrstuvwxyz'
function unpack_string()
	local s=""
	for i=1,unpack_int() do
		local c=unpack_int()
		s=s..sub(itoa,c,c)
	end
	return s
end
function unpack_models()
	-- for all models
	for m=1,unpack_int() do
		local model,name,scale={},unpack_string(),unpack_int()
		-- vertices
		model.v={}
		for i=1,unpack_int() do
			add(model.v,{unpack_float(scale),unpack_float(scale),unpack_float(scale)})
		end
		
		-- faces
		model.f={}
		for i=1,unpack_int() do
			local f={unpack_int(),unpack_int()}
			for k=1,f[2] do
				add(f,unpack_int())
			end
			add(model.f,f)
		end

		-- normals
		model.n={}
		for i=1,unpack_int() do
			add(model.n,{unpack_float(),unpack_float(),unpack_float()})
		end
		
		-- n.p cache	
		model.cp={}
		for i=1,#model.f do
			local f=model.f[i]
			add(model.cp,v_dot(model.n[i],model.v[f[1]]))
		end
				
		-- edges
		model.e={}
		for i=1,unpack_int() do
			add(model.e,{
				-- start
				unpack_int(),
				-- end
				unpack_int(),
				-- always visible?
				unpack_int()==1 and true or -1
			})
		end

		-- merge with existing model
		all_models[name]=clone(model,all_models[name])
	end
end

-- little hack to perform in-place data updates
local draw_session_id=0
function draw_model(model,m,x,y,z,w)
	draw_session_id+=1

	color(model.c)
	-- camera distance dithering
	if w then
		local d=lerp(1-mid(w/2,0,1),1,#dither_pat)
		fillp(dither_pat[flr(d)]+0.1)
	end
	
	-- cam pos in object space
	local cam_pos=v_clone(cam.pos)
	m_inv_x_v(m,cam_pos)

	-- faces
	local f,n
	for i=1,#model.f do
		f,n=model.f[i],model.n[i]
		-- viz calculation
		local d=n[1]*cam_pos[1]+n[2]*cam_pos[2]+n[3]*cam_pos[3]
		if d>=model.cp[i] then
			for k=1,f[2] do
				model.e[f[k+2]][3]=draw_session_id
			end
		end
	end
	-- edges
	local p,v={}
	for _,e in pairs(model.e) do
		if e[3]==true or e[3]==draw_session_id then
			-- edges indices
			local ak,bk=e[1],e[2]
			-- edge positions
			local a,b=p[ak],p[bk]
			-- not in cache?
			if not a then
				v=model.v[ak]
				x,y,z=v[1],v[2],v[3]
				--m_x_v(m,v)
				x,y,z,w=cam:project(m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15])
				p[ak]={x,y,z,w}
				a=p[ak]
			end
			if not b then
				v=model.v[bk]
				x,y,z=v[1],v[2],v[3]
				--m_x_v(m,v)
				x,y,z,w=cam:project(m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15])
				p[bk]={x,y,z,w}
				b=p[bk]
			end
			-- on screen? draw
			if(a[3]>0 and b[3]>0) line(a[1],a[2],b[1],b[2])
		end
	end
	fillp()
end

_g.die_plyr=function(self)
	self.disabled=true
	plyr_playing,cockpit_view=false,false
	cam.flip=false

	futures_add(function()
		-- death spin
		local death_q=make_q(v_fwd,rnd(0.04)-0.08)
		wait_async(90,function(i)
			q_x_q(plyr.q,death_q)
			return true
		end)
		make_part("blast",self.pos)
		screen_shake(4)
		del(actors,self)
		plyr=nil
	end)
end

_g.die_actor=function(self)
	make_part("blast",self.pos)
	self.disabled=true
	del(actors,self)
	-- notifies listeners (if any)
	if(self.on_die) self:on_die(true)
end

_g.update_exit=function(self)
	if(not plyr) return false
	if sqr_dist(self.pos,plyr.pos)<32 then
		-- confirmation sound
		sfx(0)
		del(actors,self)
		if (self.on_die) self:on_die(true)
		return false
	end
	return true
end

-- returns a vector from pos to offset
-- offset: position relative to other
function follow(pos,other,offset)
	local v=v_clone(offset)
	-- offset into world position
	m_x_v(other.m,v)
	-- line to target
	v_add(v,pos,-1)
	return v
end
function avoid(self,pos,dist)
	local v,n,d2={0,0,0},0,dist*dist
	for _,a in pairs(actors) do
		if a!=self then
			local d=sqr_dist(pos,a.pos)
			if d<d2 then
			 local force=1-smoothstep(d/d2)
				v_add(v,pos,force)
				v_add(v,a.pos,-force)
				n+=1
			end
		end
	end
	-- average force
	if(n>0) v_scale(v,1/n)
	return v
end
function seek(self,fwd,dist)
	for _,a in pairs(actors) do
		if not a.disabled and band(a.side,self.side)==0 and in_cone(self.pos,a.pos,fwd,0.5,dist) then
			 -- avoid loops
			if a.target!=self then
				return a
			end
		end
	end
end

-- return a pos in self space
function wander(self)
	local p=make_rnd_v(1)
	p[3]+=15
	return p
end

function update_engines(self)
	if self.model.engines and time_t%2==0 then
		for _,v in pairs(self.model.engines) do
			-- model to world
			v=v_clone(v)
			m_x_v(self.m,v)
			local p=make_part(self.model.engine_part,v)
			-- set part orientation
			p.m=self.m
		end
	end
end

--[[
function intercept(shotspeed,trp,trv)
	local v2=v_dot(trv,trv)
	if(v2<0.001) return 0
 
	local a=v2-shotspeed*shotspeed
	local b=2*v_dot(trv,trp)
	
	--handle similar velocities
	if abs(a)<0.001 then
		return max(-v_dot(trp,trp)/b)
	end

	local c=v_dot(trp,trv)
	local d=b*b-4*a*c
	if(d<=0) return 0
 
	d=sqrt(d)
	local t1=(-b+d)/(2*a)
	local t2=(-b-d)/(2*a)
	if t1>0 then
		return t2>0 and min(t1,t2) or t1
	end
	return max(t2) --don't shoot back in time
end
]]

_g.update_flying_npc=function(self)
	-- npc still in range?
	if plyr and sqr_dist(self.pos,plyr.pos)>9216 then
		-- notifies listeners (if any)
		if (self.on_die) self:on_die()
		return false
	end
	
	-- force application point 
	local pos,m={0,0,1},self.m
	-- to world
	m_x_v(m,pos)
	-- forces
	local can_fire,prev_fwd=false,m_fwd(m)
	local force=v_clone(prev_fwd)
	-- weight move ahead
	v_scale(force,5)

	local stamina=1-smoothstep(self.overg_t/8)
	if self.target and not self.target.disabled then
		-- enemy: get in sight
		local aoa=v_clone(self.pos)
		v_add(aoa,self.target.pos,-1)
		local facing=v_dot(prev_fwd,aoa)
		can_fire,target_pos=true,{rnd()-0.5,rnd()-0.5,facing>0 and -15 or 5}
		v_add(force,follow(pos,self.target,target_pos),stamina)
	else
		-- search for target
		self.target=seek(self,prev_fwd,24)
	end
	if not self.wander or self.wander_t<time_t then
		-- pick a random location
		self.wander=wander(self)
		self.wander_t=time_t+120+rnd(60)
	end
	-- add some 'noise' even when following a target
	v_add(force,follow(pos,self,self.wander),self.target and 0.2 or 1)
 	-- avoid other actors
	v_add(force,avoid(self,pos,8),2)

	-- clamp acceleration
	v_clamp(force,0.03)
	
	-- update orientation
	v_add(pos,force)
	v_add(pos,self.pos,-1)
	v_normz(pos)
	
 	-- try to align w/ target
	local up=m_up(m)
	if self.target then
		v_add(up,m_up(self.target.m),stamina*0.2)
		v_normz(up)
	end
	m=make_m_toward(pos,up)
	-- constant speed
	local fwd=m_fwd(m)
	v_add(self.pos,fwd,self.acc)
	m_set_pos(m,self.pos)
	self.m=m

	-- engine effect
	update_engines(self)
	
	-- evaluate stress
 self.g=1-abs(v_dot(prev_fwd,fwd))
 
 -- turn rate/second 	
 if self.g>0.0004 then
		self.overg_t=min(self.overg_t+2,64)
	end
	self.overg_t*=0.95

	-- fire solution?
	if self.model.wp and can_fire and self.fire_t<time_t and in_cone(self.pos,self.target.pos,fwd,0.92,24) then
 	self:fire(self.target.pos)
	end

 -- estimate position
 --[[
	local trp=v_clone(self.pos)
	v_add(trp,plyr.pos,-1)
	local trv=v_clone(fwd)
	v_scale(trv,self.acc)
	v_add(trv,m_fwd(plyr.m),-plyr.acc)
	local lead_t=intercept(all_parts["laser"].acc,trp,trv)
	
	self.lead_pos=v_clone(self.pos)
	v_add(self.lead_pos,trv,lead_t)
	self.lead_t=lead_t
	]]
 self.lead_pos=v_clone(self.pos)	
	self.lead_t=0
 
	return true
end

_g.hit_plyr=function(self,dmg)
	if(self.disabled or self.safe_t>time_t) return
	self.energy,self.safe_t=0,time_t+8
	self.hp-=dmg
	if self.hp<=0 then
		self:die()
	end
	screen_shake(2)
end

_g.draw_plyr=function(self,x,y,z,w)
	if(cockpit_view) return
	draw_model(self.model,self.m,x,y,z,w)
end

_g.update_plyr=function(self)
	-- energy
	self.energy=min(self.energy+0.005,1)
	-- refill shield + proton
	if self.energy==1 and self.hp!=5 then
		self.hp,self.energy=min(self.hp+1,5),0
	elseif self.energy==1 and self.proton_ammo!=4 then
		self.proton_ammo,self.energy=min(self.proton_ammo+1,4),0		
	end

	-- damping
	self.roll*=0.9
	self.pitch*=0.92
	self.boost*=self.dboost
	
	-- engine trail
	update_engines(self)
	return true
end

_g.hit_npc=function(self,dmg)
	-- avoid reentrancy
	if(self.disabled) return
	self.hp-=dmg
	if self.hp<=0 then
		self:die()
	end
end
_g.hit_flying_npc=function(self,dmg,actor)
	_g.hit_npc(self,dmg)
	-- todo: wait a bit
	if actor==plyr then
		self.target=plyr
	end
end

_g.update_turret=function(self,i,j)
	if(not plyr) return true
	
	self.pos[1],self.pos[2],self.pos[3]=i*ground_scale,abs(i*ground_scale)<8 and ground_level-6 or ground_level,j*ground_scale

	-- in range?
	local angle,m=1,self.m
	if sqr_dist(self.pos,plyr.pos)<16*16 then
		local dx,dy=self.pos[1]-plyr.pos[1],self.pos[3]-plyr.pos[3]
		angle=atan2(dx,dy)-0.25
		local q=make_q(v_up,angle)
		m=m_from_q(q)
		self.m=m
	end
	m_set_pos(m,self.pos)
	
	-- delay fire for new turret
	if time_t-self.local_t>45 then
		self.pause_t=time_t+rnd(45)
	end
	
	-- fly low or die!
	if plyr.pos[2]>self.pos[2]+3 and self.pause_t<time_t then
		self:fire(plyr.pos)
	end
	self.local_t=time_t
	return true
end
_g.update_junk=function(self,i,j)
	self.pos[1],self.pos[2],self.pos[3]=i*ground_scale,abs(i*ground_scale)<8 and ground_level-6 or ground_level,j*ground_scale

	m_set_pos(self.m,self.pos)
end
function make_blt(self,wp,pos,u)
	local pt=add(parts,clone(all_parts[wp.part or "laser"],{
			actor=self, -- laser owner
			pos=pos,
			u=u,
			side=self.side,
			dmg=wp.dmg,
			die_part=wp.die_part}))
	pt.t=time_t+pt.dly
	if(wp.sfx) sfx_v(wp.sfx,pos)
	return pt
end
_g.make_laser=function(self,target)
	if(self.fire_t>time_t) return false
	
	local wp=self.model.wp
	local i=self.laser_i%#wp.pos+1
	-- rebase laser in world space
	local p=v_clone(wp.pos[i])
	m_x_v(self.m,p)
	-- direction override?
	local v
	if target then
		v=v_clone(target)
		v_add(v,p,-1)
		v_normz(v) 
	else
		v=v_clone(wp.n[i])
		o_x_v(self.m,v)
	end
	self.laser_i+=1
	local pt=make_blt(self,wp,p,v)
	-- laser colors
	local c=self.side==good_side and 8 or 11
	pt.c,self.fire_t=c,time_t+wp.dly
	make_part("flash",p,c)
end

_g.make_proton=function(self,target)
	local wp=self.model.proton_wp
	-- rebase wp in world space
	local p=v_clone(wp.pos)
	m_x_v(self.m,p)
	-- fire direction in world space
	local v=v_clone(wp.n)
	o_x_v(self.m,v)

	make_blt(self,wp,p,v).target=target
end

local all_actors=json_parse'{"plyr":{"hp":5,"safe_t":0,"energy":1,"energy_t":0,"boost":0,"dboost":1,"acc":0.2,"model":"xwing","roll":0,"pitch":0,"laser_i":0,"fire_t":0,"fire":"make_laser","lock_t":0,"proton_t":0,"proton_ammo":4,"fire_proton":"make_proton","side":"good_side","draw":"draw_plyr","update":"update_plyr","hit":"hit_plyr","die":"die_plyr"},"patrol":{"hp":10,"acc":0.2,"g":0,"overg_t":0,"rnd":{"model":["xwing","xwing","ywing"]},"side":"good_side","wander_t":0,"lock_t":0,"laser_i":0,"fire_t":0,"fire":"make_laser","update":"update_flying_npc","hit":"hit_npc","die":"die_actor"},"tie":{"hp":4,"acc":0.4,"g":0,"overg_t":0,"model":"tie","side":"bad_side","wander_t":0,"lock_t":0,"laser_i":0,"fire_t":0,"fire":"make_laser","update":"update_flying_npc","hit":"hit_flying_npc","die":"die_actor","rnd":{"id":[0,128]}},"generator":{"waypt":true,"hp":10,"model":"generator","side":"bad_side","update":"nop","hit":"hit_npc","die":"die_actor"},"vent":{"waypt":true,"hp":12,"model":"vent","side":"bad_side","update":"nop","hit":"hit_npc","die":"die_actor"},"mfalcon":{"hp":8,"acc":0.25,"g":0,"overg_t":0,"model":"mfalcon","side":"good_side","wander_t":0,"lock_t":0,"laser_i":0,"fire_t":0,"fire":"make_laser","update":"update_flying_npc","hit":"hit_npc","die":"die_actor"},"turret":{"hp":2,"model":"turret","side":"bad_side","local_t":0,"pause_t":0,"fire_t":0,"laser_i":0,"fire":"make_laser","update":"update_turret","hit":"hit_npc","die":"die_actor"},"ground_junk":{"hp":2,"model":"junk2","side":"bad_side","update":"update_junk","hit":"hit_npc","die":"die_actor"},"exit":{"draw":"nop","update":"update_exit","waypt":true},"vador":{"hp":40,"acc":0.3,"g":0,"overg_t":0,"model":"tiex1","side":"bad_side","wander_t":0,"lock_t":0,"laser_i":0,"fire_t":0,"fire":"make_laser","update":"update_flying_npc","hit":"hit_flying_npc","die":"die_actor"}}'

function make_actor(src,p,q)
	-- instance
	local a=clone(all_actors[src],{
		pos=v_clone(p),
		q=q or make_q(v_up,0)
	})
	a.model,a.draw=all_models[a.model],a.draw or draw_actor
	-- init orientation
	local m=m_from_q(a.q)
	m_set_pos(m,p)
	a.m=m
	return add(actors,a)
end

local rear_q=make_q(v_up,0.5)
function make_cam(f)
	local c={
		pos={0,0,3},
		q=make_q(v_up,0),
		focal=f,
		flip=false,
		update=function(self)
			self.m=m_from_q(self.q)
			m_inv(self.m)
		end,
		track=function(self,pos,q)
			self.pos=v_clone(pos)
			q=q_clone(q)
			if self.flip then
				q_x_q(q,rear_q)
			end
			self.q=q
		end,
		project=function(self,x,y,z)
			-- world to view
			x-=self.pos[1]
			y-=self.pos[2]
			z-=self.pos[3]
			local v=m_x_xyz(self.m,x,y,z)
			-- distance to camera plane
			v[3]-=1
			if(v[3]<0.001) return nil,nil,-1,nil
			-- view to screen
 			local w=self.focal/v[3]
 			return 64+v[1]*w,64-v[2]*w,v[3],w
		end
	}
	return c
end

_g.update_part=function(self)
	if(self.t<time_t or self.r<0) return false
	self.r+=self.dr
	return true
end
_g.update_blast=function(self)
	if self.frame==8 then
		self.kind,self.dr=5,-0.2
		for i=1,self.sparks do
			local v=make_rnd_v(rnd(self.r))
			v_add(v,self.pos)
			make_part("spark",v)
		end
	end
	self.frame+=1
	return _g.update_part(self)
end

_g.die_blt=function(self)
	make_part(self.die_part or "flash",self.pos,self.c)
	-- to be removed from set
	return false
end

function blt_obj_col(self,objs)
	for _,a in pairs(objs) do
		local r=a.model and a.model.r or nil
		if r and band(a.side,self.side)==0 then
			r*=r
			local hit=false
			-- edge case: base or tip inside sphere
			if sqr_dist(self.pos,a.pos)<r or sqr_dist(self.prev_pos,a.pos)<r then
				hit=true
			else
				local ps=v_clone(a.pos)
				-- point to sphere
				v_add(ps,self.pos,-1)
				-- projection on ray
				local t=v_dot(self.u,ps)
				if t>=0 and t<=self.acc then
					-- distance to sphere?
					local p=v_clone(self.u)
					v_scale(p,t)
					hit=sqr_dist(p,a.pos)<r
				end	
			end
			if hit then
				a:hit(self.dmg,self.actor)
				return true
			end	
		end
	end
	return false
end

_g.update_blt=function(self)
	if(self.t<time_t) return false
	
	-- ground?
	if ground_level and self.pos[2]<ground_level then
		if abs(self.pos[1])>6 or self.pos[2]<ground_level-6 then
			return self:die()
		end
	end
	self.prev_pos=v_clone(self.pos)
	v_add(self.pos,self.u,self.acc)

	-- collision?
	if blt_obj_col(self,actors) or blt_obj_col(self,ground_actors) then
		return self:die()
	end
	
	return true
end

_g.update_proton=function(self)
 if time_t%2==0 then
 	make_part("trail",self.pos,10)
 end
 -- update orientation to match target
 if self.target and not self.target.disabled then
		-- old enough?
		local v=v_clone(self.target.pos)
		v_add(v,self.pos,-1)
		-- not too close?
		if v_dot(v,v)>0.25 then
			v_normz(v)
 		-- within cone?
 		if v_dot(self.u,v)>0.6 then
 			v_add(self.u,v,smoothstep(self.frame/60))
 			v_normz(self.u)
 		end
 	end
 end
 self.frame+=1
 return _g.update_blt(self)
end

_g.draw_part=function(self,x,y,z,w)
 -- laser
	if self.kind==0 then
		local x1,y1,z1,w1=cam:project(self.prev_pos[1],self.prev_pos[2],self.prev_pos[3])
		if z>0 and z1>0 then
			line(x,y,x1,y1,time_t%2==0 and self.c or 10)
		end
	elseif self.kind==1 then
  circfill(x,y,self.r*w,self.c)
	end
	--[[
	-- proton head
	elseif self.kind==3 then
		-- light effect
		fillp(dither_pat[mid(#dither_pat-flr(w/2),1,#dither_pat)])
		circfill(x,y,(0.5+rnd(1))*w,8)
		fillp()
		circfill(x,y,(0.1+0.2*rnd())*w,10)
	elseif self.kind==5 then
		circ(x,y,w*self.r,7)
	-- blast particle
	elseif self.kind==6 then
		pset(x,y,rnd(16))
	elseif self.kind==7 then
	 circ(x,y,self.r*w,self.c[flr(3-3*mid(self.r/0.4,0,1))+1])
	-- 3d line particles
	elseif self.kind==8 then
		color(self.c)
		if w>1 then
 		for _,v in pairs(self.e) do
 			v=v_clone(v)
  		m_x_v(self.m,v)
  		local x1,y1,z1,w1=cam:project(v[1],v[2],v[3])
  		if z>0 and z1>0 then
  			line(x,y,x1,y1)
  		end
 		end
 	end
	end
	]]
end

all_parts=json_parse'{"laser":{"rnd":{"dly":[40,60]},"acc":8,"kind":0,"update":"update_blt","die":"die_blt","draw":"draw_part"},"ground_laser":{"rnd":{"dly":[95,120]},"acc":0.8,"kind":0,"update":"update_blt","die":"die_blt","draw":"draw_part"},"flash":{"kind":1,"rnd":{"r":[0.5,0.7],"dly":[4,6]},"dr":-0.05},"trail":{"kind":1,"rnd":{"r":[0.2,0.3],"dly":[12,24]},"dr":-0.02},"blast":{"frame":0,"sfx":3,"kind":1,"c":7,"rnd":{"r":[2.5,3],"dly":[8,12],"sparks":[6,12]},"dr":-0.04,"update":"update_blast"},"novae":{"frame":0,"sfx":9,"kind":1,"c":7,"r":30,"rnd":{"dly":[8,12],"sparks":[30,40]},"dr":-0.04,"update":"update_blast"},"proton":{"die_part":"blast","rnd":{"dly":[90,120]},"frame":0,"acc":0.6,"kind":3,"update":"update_proton","die":"die_blt","draw":"draw_part"},"spark":{"kind":6,"dr":0,"r":1,"rnd":{"dly":[24,38]}},"purple_trail":{"kind":7,"c":[14,2,5,1],"rnd":{"r":[0.35,0.4],"dly":[2,4],"dr":[-0.08,-0.05]}},"blue_trail":{"kind":7,"c":[7,12,5,1],"rnd":{"r":[0.3,0.5],"dly":[12,24],"dr":[-0.08,-0.05]}},"mfalcon_trail":{"kind":8,"r":1,"dr":0,"e":[[-3.24,0,-5.04],[3.24,0,-5.04]],"rnd":{"c":[12,7,13],"dly":[1,2]}}}'

function make_part(part,p,c)
	local pt=add(parts,clone(all_parts[part],{pos=v_clone(p),draw=_g.draw_part,c=c}))
	pt.t,pt.update=time_t+pt.dly,pt.update or _g.update_part
	if(pt.sfx) sfx_v(pt.sfx,p)
	return pt
end

function draw_ground(self)
	local cy=cam.pos[2]

	if not ground_level then
		draw_deathstar(-6)
		draw_stars()
		return
	end
	-- rebase height
	cy-=ground_level
	if(cy<0) return
	if cy>128 then
		cy-=64
		draw_deathstar(-min(6,cy/32))
		draw_stars()
		return
	end
	
	local scale=4*max(flr(cy/32+0.5),1)
	scale*=scale
	local x0,z0=cam.pos[1],cam.pos[3]
	local dx,dy=x0%scale,z0%scale
	
	for i=-6,6 do
		local ii=scale*i-dx+x0
		-- don't draw on trench
		if abs(flr(ii-x0+cam.pos[1]))>=8 then
			for j=-6,6 do
				local jj=scale*j-dy+z0
				local x,y,z,w=cam:project(ii,ground_level,jj)
				if z>0 then
					pset(x,y,ground_colors[mid(flr(2*w),1,3)])
				end
			end
		end
	end
end
local trench_scale,turrets,trench_actors=6
function make_ground_actor(i,j,src,y)
	local x,y,z=i*ground_scale,y or 0,j*ground_scale
	local a=clone(all_actors[src],{
		pos={x,y,z},
		m=make_m(x,y,z),
		draw=draw_actor
	})
	a.model=all_models[a.model]
	turrets[i+j*128]=a
	return a
end

function make_trench(i)
	local x,y,z=0,0,i*trench_scale
	local t={
		pos={x,y,z},
		m=m_from_q(make_q(v_up,i%2==0 and 0.5 or 0)),
		side=no_side,
		model=all_models["trench1"],
		update=function(self)
			local dz=cam.pos[3]-cam.pos[3]%(2*trench_scale)
			local z=i*trench_scale+dz			
			self.pos[2],self.pos[3],self.m[14],self.m[15]=ground_level,z,ground_level,z
			return true
		end,
		draw=function(self,x,y,z,w)
		 if(w>1) draw_model(self.model,self.m,x,y,z,w)
		 -- no lod
		end
	}
	m_set_pos(t.m,t.pos)
	add(trench_actors,t)
end

function init_ground()
	-- reset globals
	turrets,trench_actors={},{}
	for i=0,127 do
		for j=0,127 do
		 -- force turret!
			local r=(i%124==2 and j%16==0) and 1 or rnd()
			if r>0.995 then
				make_ground_actor(i,j,"turret")
			elseif r>0.98 then
				make_ground_actor(i,j,"ground_junk")
			end
		end
	end
	for i=-10,10 do
		make_trench(i)
	end
end

function update_ground()
	ground_actors={}
	-- don't activate ground actors
	if(not ground_level) return
	
	local pos=plyr and plyr.pos or cam.pos
	-- crude viz check
	if(pos[2]>ground_level+96) return

	local i0,j0=flr(pos[1]/ground_scale),flr(pos[3]/ground_scale)
	for i=i0-9,i0+9 do
		local cx=(i%128+128)%128
		for j=j0-9,j0+9 do
			local cy=(j%128+128)%128
			local t=turrets[cx+cy*128]			
			if t and not t.disabled then
				t:update(i,j)
				add(drawables,t)
				add(ground_actors,t)
			end
		end
	end
	-- trench
	for _,t in pairs(trench_actors) do
		t:update()
		add(drawables,t)
	end
end


local turn_t=0

function plyr_ground_col(pos)
	-- ground collision?
	if ground_level and pos[2]<ground_level then
		local r,col=rnd()*0.4,false
		if abs(pos[1])<=6 then
			if pos[1]>=5.9 then
				pos[1],col=5.5-r,true
			elseif pos[1]<=-5.9 then
				pos[1],col=-5.5+r,true
			end
			if pos[2]<ground_level-6 then
				pos[2],col=ground_level-5.5+r,true
			end
			-- between trench walls?
			if(not col) return false
		else
			pos[2]=ground_level-r
		end
		-- take damage
		plyr:hit(1)
		return true
	end
	return false
end

local view_changing,cockpit_offset,outside_offset=false,{0,0,0},{0,2,-8}
function set_view(target_view)
 -- nothing to do?
	if(view_changing or cockpit_view==target_view) return
	view_changing=true
	futures_add(function()
		local c=cockpit_view
		cockpit_view=false
		wait_async(30,function(i)
			view_offset=v_lerp(
				c and cockpit_offset or outside_offset,
				target_view and cockpit_offset or outside_offset,
				smoothstep(i/30))
			return true
		end)
		cockpit_view,view_changing=target_view,false
	end)
end

function find_closest_tgt(fwd,objs,min_dist,target)
	min_dist=min_dist or 32000
	for _,a in pairs(objs) do
		if a.hp and band(a.side,plyr.side)==0 then
			local d=sqr_dist(a.pos,plyr.pos)
			if d>2 and d<min_dist and in_cone(plyr.pos,a.pos,fwd,0.5,64) then --0.98,64) then
				min_dist,target=d,a
			end
			-- collision?
			local r=plyr.model.r+a.model.r
			-- todo: sound
			if(d<r*r) plyr:hit(1)
		end
	end
	return min_dist,target
end

-- handle player inputs
-- todo: better split w/ update
function control_plyr(self)
	
	local pitch,roll=0,0
	if plyr_playing then
	 -- ⬅️⬆️⬇️➡️🅾️❎
		if(btn(0)) roll=-1 turn_t+=1
		if(btn(1)) roll=1 turn_t+=1
		if(btn(2)) pitch=-1
		if(btn(3)) pitch=1
		-- flip y-axis?
		pitch*=invert_y
		
		-- cam modes
		if btnp(2,1) then
			set_view(not cockpit_view)
		end
		-- behind look?
		cam.flip=btn(3,1)

		-- boost 
		if btn(4) then
			plyr.boost=min(plyr.boost+0.05,2*plyr.acc)
		end
	end
	
	-- flat turn
	turn_t=min(turn_t,16)
	if roll!=0 then
		self.roll=-roll/256
	else
		turn_t=0
	end
 	self.roll=mid(self.roll,-0.01,0.01)
	local r=turn_t/16
	local q=make_q(v_up,(1-r)*roll/128)
	q_x_q(plyr.q,q)
	q=make_q(v_fwd,-r*roll/128)
	q_x_q(plyr.q,q)
	
	if pitch!=0 then
		self.pitch-=pitch/396
	end
	local pitch_max=plyr.boost>0 and 0.002 or 0.004
	self.pitch=mid(self.pitch,-pitch_max,pitch_max)
	
	local q=make_q(v_right,self.pitch)
	q_x_q(plyr.q,q)
	
	-- update pos
	local m=m_from_q(self.q)
	local fwd=m_fwd(m)
	v_add(self.pos,fwd,self.acc+self.boost)
	plyr_ground_col(self.pos)	
	m_set_pos(m,self.pos)
	self.m=m
	
	if plyr_playing then
 	-- find nearest enemy (in sight)
 	local min_dist,target=find_closest_tgt(fwd,actors)
 	-- find nearest ground actors
 	min_dist,target=find_closest_tgt(fwd,ground_actors,min_dist,target)
 	
 	plyr.target=target
 	if target then
 		plyr.lock_t+=1
 	else
 		plyr.lock_t=0
 	end
 	if self.lock_t==30 then
 		sfx(7)
 	end
 	if plyr.proton_ammo>0 and plyr.proton_t<time_t and plyr.lock_t>30 and btnp(4) then
 		--plyr:fire_proton(target)
 		plyr.proton_t=time_t+plyr.model.proton_wp.dly
 		plyr.proton_ammo-=1
 		plyr.energy=0
 	end
 		
 	if self.fire_t<time_t and btn(5) then 		
 		if(plyr.energy>0.08) plyr:fire(target and target.pos or nil)
 		plyr.energy=max(plyr.energy-0.08)
 	end
 end
end

-- deathstar
local ds_m,ds_scale,ds_enabled=make_m(),0,false
function draw_deathstar(offset)
	if ds_enabled then
		m_set_pos(ds_m,{cam.pos[1],ds_scale+offset+cam.pos[2],cam.pos[3]})
		draw_model(all_models["deathstar"],ds_m)
	end
end

local stars,stars_ramp={},json_parse'[1,13,6,7]'
function draw_stars()
	local hyper_space=plyr and plyr.boost>0
 for _,v in pairs(stars) do
		local x,y,z,w=cam:project(v[1],v[2],v[3])
		if z>0 and z<32 then
			color(stars_ramp[min(flr(4*w/12)+1,#stars_ramp)])
			if hyper_space and v.x then
				line(v.x,v.y,x,y)
			else
				pset(x,y)
			end
			v.x,v.y=x,y
		else
			-- reset pos
			local star=make_rnd_v(32)
			v[1],v[2],v[3]=star[1],star[2],star[3]
			v.x,v.y=nil,nil
			v_add(v,cam.pos)
		end
	end
end

local radar_colors,shield_spr=json_parse'[5,11,3]',json_parse'[72,14,45,43,74]'
function draw_radar_dots(objs)
	for _,a in pairs(objs) do
		if a!=plyr then
			local v=v_clone(a.pos)
			m_inv_x_v(plyr.m,v)
			local x,y,c=64+0.2*v[1],116-0.2*v[3],mid(flr(v[2]/8),-1,1)+2
			pset(x,y,radar_colors[c])
		end
	end
end

function draw_instr()
	clip(54,105,20,22)
	draw_radar_dots(ground_actors)
	draw_radar_dots(actors)
	clip()
	
	-- draw waypoints
	for _,a in pairs(actors) do
		if a.waypt then
 			local x,y,z,w=cam:project(a.pos[1],a.pos[2],a.pos[3])
 			if z>0 and w<4 then
 				x,y=mid(x,4,124),mid(y-2*w,4,124)
 				spr(41,x-4,y-4)	
			end
		end
	end
	
	-- draw lock
	if plyr.target and plyr.lock_t>30 then
		local p=plyr.target.lead_pos
		local x,y,z,w=cam:project(p[1],p[2],p[3])
		if z>0 then
			w=max(w,4)
			spr(40,x-w,y-w)
			spr(40,x+w-8,y-w,1,1,true)
			spr(40,x-w,y+w-8,1,1,false,true)
			spr(40,x+w-8,y+w-8,1,1,true,true)
			--print(60*plyr.target.lead_t.."s",x,y-w-8,6)
		end
	end
	
	-- proton ammo
	for i=0,plyr.proton_ammo-1 do
		local x,y=77+(i%2)*6,102+6*flr(i/2)
		spr(42,x,y)
	end

 	-- shield
 	spr(shield_spr[max(plyr.hp,1)],39,104,2,2)
 	if plyr.hp!=5 and time_t%4<2 then
		spr(shield_spr[max(plyr.hp+1,1)],39,104,2,2)
	end
end

-- https://8bit-caaz.tumblr.com/post/171458093376/layering-sprite-data
-- base colors={0,1,0,14}
function set_layer(top)
	if top then
		poke4(0x5f00,0x0e00.0180)
		poke4(0x5f04,0x0e00.0180)
		poke4(0x5f08,0x0e00.0180)
		poke4(0x5f0c,0x0e00.0180)
	else
		poke4(0x5f00,0x8080.8080)
		poke4(0x5f04,0x0101.0101)
		poke4(0x5f08,0x0000.0000)
		poke4(0x5f0c,0x0e0e.0e0e)
	end
end

-- wait loop
local start_screen_starting=false
function start_screen:update()
	if not start_screen_starting and (btnp(4) or btnp(5)) then
		-- avoid start reentrancy
		start_screen_starting=true	 
		sfx(0)
		music(-1,500)
		futures_add(function()
			wait_async(30)
				-- select next screen
			cur_screen=game_screen
			-- init game
			time_t,cockpit_view,view_offset,actors,parts,ground_level=0,false,outside_offset,{},{},nil
			plyr,plyr_playing=make_actor("plyr",{0,300,0},make_q(v_right,0.25)),false
			-- hyperspace!
			plyr.boost,plyr.dboost=1,1.01
			init_ground()
			sfx(10)
			-- deathstar zooming effect
			wait_async(180,function(i)
				ds_enabled,ds_scale=i>80,lerp(-150,0,smoothstep((i-90)/90))
				return true
			end)
			plyr.boost,plyr.dboost=0,0.9
			-- move to cockpit view
			set_view(true)
			plyr_playing=true

			-- init mission wait loop			
			futures_add(next_mission_async)
			start_screen_starting=false
		end)
	end
end

local title_m=make_m(0,0,0)
--local all_help=json_parse'[{"msg":"⬅️⬆️⬇️➡️: flight control","x":20},{"msg":"menu: invert y-axis","x":30},{"msg":"❎: laser / 🅾️+lock: torpedo","x":12},{"msg":"🅾️: speed boost","x":34},{"msg":"⬇️[p2]: rear view","x":30},{"msg":"⬆️[p2]: external view","x":23}]'
function start_screen:draw()
	cam.pos[3]+=0.1
	cam:update()
	draw_stars()
	m_set_pos(title_m,{-0.94,0.4,2.1+cam.pos[3]})
	draw_model(all_models["logo"],title_m)
	print("freds72 presents",32,4,1)
	print("attack on the death star",20,78,12)
	
	--[[
	local i=flr(time_t/128)%#all_help
	local h=all_help[i+1]
	print(h.msg,h.x,108,3)
	]]
	
	if (start_screen_starting and time_t%2==0) or time_t%24<12 then
		print("press start",44,118,11)
	end
end

function wait_gameover_async()
	wait_async(60)
	cur_screen=gameover_screen
	wait_async(600,function()
		if btnp(4) or btnp(5) then
			-- "eat" btnp to avoid immediate restart
			yield()
			return false
		end
		return true
	end)
	camera()
	music(0)
	cam,cur_screen=make_cam(64),start_screen
end

function gameover_screen:update()
	q_x_q(cam.q,make_q(v_up,0.001))
	game_screen:update()
end

function gameover_screen:draw()
	game_screen:draw()
	print("game over",46,60,12)
	print("achieved: "..score.."/4",39,70,10)
	
 -- display badges
	for i=1,4 do
		spr(i<=score and 57 or 108,29+11*i,80,2,1)
	end
end

-- play loop
function game_screen:update()
	zbuf_clear()
	
	-- comms
	update_msg()
	
	if plyr then
		control_plyr(plyr)
		-- do not track dead player
		if not plyr.disabled then
			-- update cam
			cam:track(m_x_xyz(plyr.m,view_offset[1],view_offset[2],cam.flip and -view_offset[3] or view_offset[3]),plyr.q)
		end
	end
	
	update_ground()

	zbuf_filter(actors)
	zbuf_filter(parts)
	
	-- must be done after update loop
	cam:update()
end

function game_screen:draw()
	draw_ground()
	
	zbuf_draw()
	
	draw_msg()
		
	-- draw cockpit
	if plyr then
		if cockpit_view then
			if not cam.flip then

				-- cockpit
				set_layer(false)
				spr(0,0,64,8,8)
				spr(0,64,64,8,8,true)
				set_layer(true)
				spr(64,0,32,8,4)
				spr(64,64,32,8,4,true)
				pal()
				-- radar & core instruments
				draw_instr()
				-- hp
				local x,imax=23,flr(8*plyr.energy)+1
				for i=1,8 do
					rectfill(x,120,x+1,123,i<imax and 11 or 1)
					x+=3
				end
				-- engines
				local p=0.5*(plyr.acc+plyr.boost)/plyr.acc
				fillp(0x5555)
				rectfill(82,120,82+23*p,123,9)
				fillp()
			else
				set_layer(true)
				spr(0,0,32,8,4)
				spr(0,64,32,8,4,true)
				-- seat
				rectfill(0,64,127,127,0)
				rect(19,64,108,125,1)
				pal()
			end
		else
			draw_instr()
		end
	end
end

function _update60()
	time_t+=1
	futures_update(before_update)
	
	cur_screen:update()
	
	screen_update()
end

function _draw()
	cls(0)

	cur_screen:draw()
	
	-- if(draw_stats) draw_stats()
	-- print(flr(100*stat(1)).."% @"..stat(7).."fps",2,2,7)
end


function _init()
	if cartdata("freds72_xvst") then
		invert_y=dget(0)
	end
	menuitem(1,"invert y-axis", function() 
		invert_y=invert_y==-1 and 1 or -1
		sfx(0)
		dset(0,invert_y)
	end)
	-- read models from map data
	unpack_models()
	
	-- compute xwing laser aim
	--[[
	local wp=all_models["xwing"].wp
	for i=1,#wp.pos do
		local v=v_clone(wp.pos[i])
		v={-v[1],-v[2],48-v[3]}
		v_normz(v)
		printh("["..v[1]..","..v[2]..","..v[3].."}")
		add(wp.n,v)
	end
	]]
	
	-- stars
	for i=1,48 do
		add(stars,make_rnd_v(32))
	end
		
	cam=make_cam(64)
	
	cur_screen=start_screen
	music(0)
end

-->8
-- radio messages
local all_msgs=json_parse'{"attack1":{"spr":12,"title":"ackbar","txt":"clear tie squadrons","dly":300},"ground1":{"spr":12,"title":"ackbar","txt":"destroy shield\ngenerators","dly":300},"ground2":{"spr":12,"title":"ackbar","txt":"bomb vent","dly":300},"victory1":{"spr":104,"title":"han solo","txt":"get out of here son.\nquick!","dly":300},"victory2":{"spr":12,"title":"ackbar","txt":"victory!","dly":300},"victory3":{"spr":8,"title":"leia","txt":"the rebellion\n thanks you.\nget back home!","dly":300},"help":{"spr":10,"rnd":{"title":["red leader","alpha","delta wing"]},"txt":"help!","dly":300},"vador_out":{"spr":106,"title":"d.vador","txt":"i\'ll be back...","dly":300},"low_hp":{"spr":76,"title":"r2d2","txt":"..--.-..","dly":120,"sfx":5,"rnd":{"repeat_dly":[600,900]}}}'
local low_hp_t,cur_msg=0

function make_msg(msg)
	local m=clone(all_msgs[msg])
	cur_msg,m.t=m,time_t+m.dly
	if (m.sfx) sfx(m.sfx)
	return m
end

function update_msg()
	if cur_msg and cur_msg.t<time_t then
		cur_msg=nil 
	end
	
	if plyr and plyr.hp<2 and low_hp_t<time_t and rnd()>0.95 then
			make_msg("low_hp")
			low_hp_t=time_t+cur_msg.repeat_dly
	end
end
function draw_msg()
	if(not cur_msg) return
	local y=2
	rectfill(32,y,49,y+18,0)
	rect(32,y,49,y+18,1)
	spr(cur_msg.spr,33,y+1,2,2)
	print(cur_msg.title,51,y,9)
	print(cur_msg.txt,51,y+7,7)
	-- cheap comms static effect
	if time_t%4>2 then
		fillp(0b1011000011110100.1)
		rectfill(33,y,48,y+23,0)
		fillp()
 end
end

-->8
-- missions
_g.create_generator_group=function()
	return { 
		make_actor("generator",{256,ground_level+6,256}),
		make_actor("generator",{-256,ground_level+6,256}),
		make_actor("generator",{-256,ground_level+6,-256}),
		make_actor("generator",{256,ground_level+6,-256})
	}
end
_g.create_vent_group=function()
	return {make_actor("vent",{0,ground_level-6,128})}
end

_g.create_flying_group=function()
	local p,v=make_rnd_pos_v(plyr,64)
	-- default target: player
	local target,n,dly=plyr,3,60+rnd(30)
	-- friendly npc?
	if rnd()>0.8 then
		target=make_actor("patrol",p)
		make_msg("help")
		v_add(p,v,10)
		-- remove firing delay
		dly=0
		-- avoid too many ties with npc
		n-=1
	end
	-- spawn new enemies
	local npcs={}
	for i=1,1+rnd(n) do
		local a=make_actor("tie",p)
		-- lock on target
		-- delay npc firing
		a.target,a.fire_t=target,time_t+dly
		v_add(p,v,10)
		add(npcs,a)
	end
	return npcs
end
_g.ingress_mission=function()
	-- set ground level
	ground_level=plyr.pos[2]-300
	return {make_actor("exit",{cam.pos[1],ground_level+30,cam.pos[3]})}
end
_g.egress_mission=function()
	return {make_actor("exit",{cam.pos[1],ground_level+300,cam.pos[3]})}
end
_g.victory_mission=function()
	cam.flip,plyr_playing=true,false
	set_view(false)
	wait_async(180)
	-- blast deathstar
	make_part("novae",{cam.pos[1],cam.pos[2]-32,cam.pos[3]})
	-- hide deathstar
	ds_enabled,ground_level=false
	wait_async(60)
	set_view(true)
	cam.flip,plyr_playing=false,true
	
	-- track dark vador
	local x,y,z=plyr.pos[1],plyr.pos[2],plyr.pos[3]
	local npc,wing=make_actor("vador",{x,y+32,z}),make_actor("mfalcon",{x,y+24,z})
	wing.target=npc
	-- mark rendez-vous point
	make_actor("exit",{x,y+30,z})
	return {npc}
end
_g.gameover_mission=function()
	plyr.disabled=true
	set_view(false)
	wait_async(90)
	del(actors,plyr)
	plyr=nil
	return {}
end

local all_missions=json_parse'[{"msg":"attack1","init":"create_flying_group","music":11,"dly":90,"target":8},{"msg":"ground1","music":11,"init":"ingress_mission"},{"init":"create_generator_group","target":4},{"msg":"ground2","init":"create_vent_group","target":1},{"msg":"victory1","init":"egress_mission","dly":600},{"init":"victory_mission","music":11,"target":1,"dly":30},{"msg":"vador_out","dly":600},{"msg":"victory3","music":14,"init":"gameover_mission","dly":720}]'

function next_mission_async()
	score=0
	for i=1,#all_missions do
		local m=all_missions[i]
		-- play music at start of new mission
		music(m.music or -1,500)
		-- wait until message completes
		if m.msg then
			wait_async(make_msg(m.msg).dly)
		end
		
 	local kills,target=0,m.target or 0
		repeat
			-- create mission
			local npcs=0
			-- any mission logic?
			if m.init then
				for _,a in pairs(m.init()) do
					npcs+=1
					-- die hook
					a.on_die=function(killed)
						npcs-=1
						if(killed) kills+=1
					end
				end
			end
			-- wait kills
			while plyr and npcs>0 do
				yield()
			end
			-- game over
			if(not plyr) goto gameover
			
			-- failed?
			if(m.mandatory and kills!=target) goto gameover

			-- pause before next mission?
			if(m.dly) wait_async(m.dly)			
		until kills>=target
		-- don't record transitions
		score+=target>0 and 1 or 0
	end
::gameover::
	wait_gameover_async()
end

-->8
-- stats
--[[
local cpu_stats={}

function draw_stats()
	-- 
	fillp(0b1000100010001111)
	rectfill(0,0,127,9,0x10)
	fillp()
	local cpu,mem=flr(100*stat(1)),flr(100*(stat(0)/2048))
	cpu_stats[time_t%128+1]={cpu,mem}
	for i=1,128 do
		local s=cpu_stats[(time_t+i)%128+1]
		if s then
			-- cpu
			local c,sy=11,s[1]
			if(sy>100) c=8 sy=100
			pset(i-1,9-9*sy/100,c)
		 -- mem
			c,sy=12,s[2]
			if(sy>90) c=8 sy=100
			pset(i-1,9-9*sy/100,c)
		end
	end
	if time_t%120>60 then
		print("cpu:"..cpu.."%",2,2,7)
	else
		print("mem:"..mem.."%",2,2,7)
	end
end
]]
-->8
-- futures (e.g. coroutines)
local futures={}
function futures_update()
	for _,f in pairs(futures) do
		local cs=costatus(f)
		if cs=="suspended" then
			assert(coresume(f))
		elseif cs=="dead" then
			del(futures,f)
		end
	end
end
-- registers a new coroutine
function futures_add(fn)
	return add(futures,cocreate(fn))
end
-- wait until timer elapses or user supplied function returns false
function wait_async(t,fn)
	local fn=fn or nop
	for i=1,t do
		if(not fn(i)) return
		yield()
	end
end
__gfx__
99988888888888888884000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000
aaa99999888888888888400000000000000000000000000000000004000000000000000000000000000000000000000000000012990000000000000000000000
aaaaaaaa999998888888840000000000000000000000000000000004400000000000000000000000000000066000000000000124499000000000000000000000
5aaaaaaaaaaaa9999988884000000000000000000000000000000000000000000000000000000000000011566666000000000124449000000000000000000000
05599999aaaaaaaaaa99999511111111111111111111111111111111111111110000045499400000000111577666600000000242449000000000070000000000
000488889999999aaaaaaaaa62222222222222222222222222222226622222220090549454940900001115577777660000002424944900000000070000000000
00004488888888899aaaa999951111111111111111111111111111151111111104454449454954400011155777777600000444424944400000b07770b0000000
000000448888888889aa98888840000000000000000000000000000400000000044544dffd445440001d999dd999d7000049a444944a940000b00000b0000000
000000004888888889aa98888884000000000000000000000000000400000040054544ffff4455400019999999979700004a04400940a400000bbbbb00000000
00000000044888889aaa9888888840000000000000000000000000004000004000504f0ff0f4050000199999999996000029a404404a92000000000000000000
00000000000448889aa98888888884000000000000000000000000000444444000005ffffff50000000d999ff999d00000024444444420000000000000000000
0000000000000449aaa98888888888400000000000000000000000000000000000000ffffff00000000dffffffffd00000000240042000000000000000000000
0000000000000005aa988888888888840000000000000000000000000000000000000df88fd0000000005ff00ff5000000000714427000000000000000000000
0000000000000012669888888888888840000000000000000000000000000000000000dffd000000000005f00f50000000006711117600000000000000000000
00000000000000122144888888888888840000000000000000000000000000000000076666700000000000577500000000776561176677000000000000000000
00000000000000122100448888888888884000000000000000000000000000000006776677776000000000000000000000666655666666000000000000000000
000000000000012221000048888888888884000000000000000000000000000088000000aaaaaaaa000000000000000000000000000000000000000000000000
000000000000012210000004488888888888400000000000000000000000000080000000a000000a000000000000000000000000000000000000000000000000
000000000000122210000000044888888888840000000000000000000000000000000000a000000a00b0b000000bbbbb00000000000bbbbb0000000000000000
0000000000001221000000000004488888888840000000000000000000000000000000000a0000a00b000b0000b00000b000000000b00000b000000000000000
0000000000112221000000000000048888888884000000000000000000000000000000000a0000a00000000000b00700b000000000b00700b000000000000000
00000001112222100000000000000044888888884000000000000000000000000000000000a00a000b000b000000070000000000000007000000000000000000
00001112222222110000000000000000448888888400000000000000000000000000000000a00a0000b0b000b0b07770b0b0000000b07770b000000000000000
011122222222221210000000000000000048888888400000000000000000000000000000000aa00000000000b0b00000b0b0000000b00000b000000000000000
12222222222211222100000000000000000448888884000000000000000000000b0b000000000a0000a00000b00bbbbb00b00000000bbbbb0000000000000000
2222222221112222221000000000000000000448888844444444444444444444b00000000000a00aa00a00000b0000000b000000000000000000000000000000
222222211222222222210000000000000000488888888888888888888888888800000000000a09aaaa90a00000bbbbbbb0000000000000000000000000000000
2222111222222222222210000000000000048888888888888888888888888888b0000000000a009aa900a0000000000000000000000000000000000000000000
211122222222222222222111111111111159999999999999999999999999999900000000000a000aa000a0000000000000000000000000000000000000000000
1222222222222222222221222222222226aaaaaa66666666666666666666666600000000000aa00aa00aa0000000000000000000000000000000000000000000
222222222222222222221222222222226aaaaaa6aaaaaaaaaaaaaaaaaaaaaaaa0000000000009aaaaaa900000000000000000000000000000000000000000000
22222222222222222221221111111115999999599555555555555555555555550000000000000999999000000000000000000000000000000000000000000000
0000000000000000000000000000004888888488488888888888888888888888000000000000000000bbbbbbb0000000000000000000000001d6000000000000
000000000000000000000000000004888888488488888888888888888888888800000000000000000b0000000b00000000000000000000000000000000000000
00000000000000000000000000004888888488488888888888888888888888880000000000000000b00bbbbb00b0000000000000000000000000000000000000
00000000000000000000000000048888884884888888888888888888444444440000000000000000b0b00000b0b0000000000000000000000000000000000000
00000000000000000000000004488888848848888888888888888884888888880000070000000000b0b00700b0b0000000000000000000000000000000000000
00000000000000000000000448888888488488888888888888888884888888880000070000000000000007000000000000000055660000000000000000000000
00000000000000000000004888888884884888444444444444488848888888880000777000000000b0b07770b0b0000000005561167600000000000000000000
00000000000000000000448888888848848884888888888888848848888888880000000000000000b0b00000b0b0000000056617016760000000000000000000
00000000000000000044888888888488488884888888888888848844444444440000000000000000b00bbbbb00b0000000566610016776000000000000000000
000000000000000004888888888848848888848888888888888484888888888800000000000000000b0000000b00000000566611116676000000000000000000
0000000000000004488888888884884888888488888888888884848888488888000000000000000000bbbbbbb000000005611666666676600000000000000000
00000000000004488888888888488488888884888888888888848488888888880000000000000000000000000000000005666666666666600000000000000000
00000000000448888888888884884888888884888888888888848488888488880000000000000000000000000000000005611616111616600000000000000000
10000000004888888888888848848888888884888888888888848488888888880000000000000000000000000000000005666616181616600000000000000000
21000000448888888888888488488888888884888888888888848488888848880000000000000000000000000000000001550000005575100000000000000000
22100044888888888888884884888888888884888888888888848488888888880000000000000000000000000000000001566166111666100000000000000000
22214488888888888888848848888888888884888888888888848488888884880000000000000000000000000000000000000500005000000000000000000000
22269888888888888888488488888888888884888888888888848488888888880000000000000000000000000000000000005005500500000000000000000000
266aa988888888888884884888888888888884888888888888848488888888480000000000000000000005507700000000050155551050000000000000000000
6aaaaa98888888888848848888888888888884888888888888848488888888880000000000000000000051515570000000050015510050000000000000000000
aaaaaaa9888888888488488888888888888888444444444444488444888888840000000000000000000111616555000000050005500050000000000000000000
aaaaaaaa988888884884888888888888888888888888888888888488888888840000000000000000000111616555000000055005500550000000000000000000
aaaaaaaaa98888848848884444444444444444444444444888888488888888880000044499400000000166616665000000001555555100000000000000000000
aaaaaaaaaa9888488488848888888888888888888888888488888488888888880000444994440000001600050006500000000111111000000000000000000000
aaaaaaaaaaa98488488884888888888888888888888888848888848888888888000044ffff440000001600606006500000000000000000000000000000000000
aaaaaaaaaaaa588488888488888888888888888888888884888884888888888800004f0ff0f40000016066070660650000000000000000000000000000000000
aaaaaaaaaaa6a94888888488888888888888888888888884888884888888888800005ffffff50000016000565000650000000000000000000000000000000000
aaaaaaaaaa6aa69888888488888888888888888888888884888884888888888800000ffffff00000011007161700550000000000000000000000000000000000
aaaaaaaaa6aa6aa9888884888888888888888888888888848888848888888888000009f00f900000000100000001000000000000000000000000000000000000
aaaaaaaa6aa6aaaa9888884444444444444444444444444888888488899999980000009ff9000000001015c58510100000000000000000000000000000000000
aaaaaaa6aa6aaaaaa988888888888888888888888888888888888488988888980000111551110000010108255301010000000000000000000000000000000000
aaaaaa6aa6aaaaaaaa98888888888888888888888888888888888845444444440001111771111000001010101010100000000000000000000000000000000000
c090f001c0f131e1f1c0d110f16738f8673898273848c63848962878a628d8e6282937283908080a4708e99608792608c8260847960896470826080806c80826
790896e90847e908c8790879c808e90a0808060808261808962808473808083808c83808792808e9180800000220101030201040301050401060501070601080
7010108010a09010b0a010c0b010e0d010f0e01001f010110110211110312110514110615110906110918110a19110b1a110c1b110d1c110e1d110f1e11081c0
10d0811071311041711071f11050510291614010800a060a0a060606060606060a6908696908a6a608a6a60869505040a0c0b090104030905010204050b07040
304070c080605040302080a050080a08f998080898161698080898f9c01020001040001050002030002060003040003070004080005060005080006070007080
0030f1410110f3d89708379708270887e80887377808d87808e80888270888e9c708e908c7e94808e9084826c7082608c72648082608482608a526bad626ba39
26086a2655392655d6e908a5e9bad6e9ba39e9086ae95539e955d6080809a768e867a88857b80867a887a768278708e8870827a7a7e8676788575708676787a7
a7270887e808278808070808278708872768a7e8a86788b85708a8678768a7278808e88808276868e8a8a888b8b808a8a8876868270888e808e88808090808e8
8708882713604060d0b0e0704070e0c0f0104030f0a0014040100190d0504080514161804040712151204020811171304050613181d34075167206b330f55226
e34085068246c34065266216f34095469236f14062d233b222409284c4c2e1305256d280403343e2a24240c47413233230566643824003a373936240e2c353b3
9240139383d37240f2b363a352306676c3b2405334e324e24083541444c2406324f364a230768634d24073640454334014d6c6b4304020450374f2308696d430
408482b6500340e3d435a45340c6e61525204040a2f245433096a655428023d344b425a536c25040b672b28070403555e494a34015b595a58340f4d575c56330
a6f5e5934005c585b57340e4e565d5404060f605e660407094f4f6104007f3a4304040d6040710135879b65879595896595896b6b77959b79659b796b6b779b6
47d988d788f947d9877769697769a6a69869a698a68738f9a67769a677a687d7f947368777a66977a6a6473688d787f998a66998a6a6c836883887f9c8368769
77a636478788d7f936c8876977696998a63647888838f908080636c8886998699869a6c8d9883888f9c8d987986969d9c887d9c888d94788d947870740100030
2000107000802000503000604000607000805000a0900090c000b0a000b0c00040a000b06000c07000901000e0d00001d000f0e00001f000800100f0500020d0
0030e000211110312110413110514110615110116110817110918110a19110b1a110c1b11071c110d1e100e1f100f1020002120012220062800080f100224200
e13200526200627200728200829200429200328000325200a2b200b2c200c2d200d2e200d2820072c200b2620052a200e29200f2030003130013230023330003
b200a2f20033e200d2230013c20082300030120070730003700053330030420043f20063730073830083930093a300a35300437000207200634300b3c300c3d3
00d3e300e3f300f3a30093e300d3830073c300b36300d1b30002d300c3f100e1b300f3220012e300d13200d15200d1a200d1f200d14300d16300500200405300
234000409300608300101300503222419121101453799653790853793b75c80875c8e5c639e5f658e5c63908f6580827e808c639c4f658c427e8c4bc7996bc79
08bc793b9ac8089ac8e54939e51958e5493908195808e8e8084939c41958c4e8e8c453969653960853963b7547087547e5c6d6e5f6b7e5c6d608f6b708272708
c6d6c4f6b7c42727c4bc9696bc9608bc963b9a47089a47e549d6e519b7e549d60819b708e8270849d6c419b7c4e827c437377537e8753737d837e8d8d83775d8
e875d837d8d8e8d8a7b7aea758ae68b7ae6858ae08f7df925040b090a050b04051413101c040d0f06121a040c0e01161703041b0604040a0c0f0802140b102f1
1281406292a2b2914082c252327140c27242224130c112a21140e1522202f140136353735240c3f304146240e324b393424024d3a3831230237304e14043b383
63c240d4b4c4742340756555253340f41585451340e4053585e23065d484b240c4e415a45340a5b5c595c340f59686a6b340f516260693402646a5367340d506
3695c340e5b54616043086f607b340d5b666968340e5a676c67340c5c656b6f33066e6f6e3307607d6d33056d6e6b0300121115230d3e3c32330254535813072
82629267e90806c708e9570879790808080608080aa8e9080ac70826570896790808080608080a672608064808e9b80879960808080608080aa826080a480826
b80896960808080608080a0608080a08280a0808080806080608080a08e908a8080638080a3806082808166808e9a82608a80808060808060808060808060710
2010203010501010402010405000507000709010409000608000408000506000a0800090c00080b00090a000c0b000b0d000c0d00070c000706000b06000a0d0
00e0f010f0011021e01011f01011210021410041611011610031510011510021310071510061910051810061710091810081a10091a100419100413100813100
71a100b1c110c1d110f1b110e1c110e1f100f11200123210e13200022200e12200f1020042220032620022520032420062520052720062720012620012020052
020042720082921092a210c28210b29210b2c200c2e200e20310b20300d2f200b2f200c2d20013f200033300f22300031300332300234300334300e23300e2d2
0023d200134300735300536300638300837300b3730083c300c3b30093b300c3a300a39300539300a36300e3d300f3d300e3040004f300b3f30004c30073d300
e3830014e300d31400f31400140400504222419121100667d72567682567d72a67682aa8d725a86825a8d72aa8682a98d7bd77d85a7838cdf697fa77d7bd9738
cd98d85a1997faa818e5a818570a18e50a185787682687688788682688688787a82687a88788a82688a8879a47480a97480a38489a88481b38481b97489a87a8
3ab7a83a18a89a48a8ea18a8eab7a89a47f40a97f40a38f49a88f41b38f41b97f49ab7446ac7446a08449a1844ba0844bac7449a47d10a97d10a38d19a88d11b
38d11b97d16718e56718570618e5061857754748069748063848758848f43848f497487587a8d5b7a8d518a87548a82518a825b7a87547f40697f40638f47588
f4f438f4f497f475b744a5c744a5084475184455084455c7447547d10697d10638d17588d1f438d1f497d1c708cd4808cdc7083e48083e93104020304010a040
f0e021b170407090a0805040a0c020b030405080b01080406030c090c04031b161117040509141810140411151d030404071319180407081a1c1f040a1d001e0
404060c1f071904051612101c140625282725140429282a2814022b262c2714032c27292614012a252b2d140a38393231240c363b303f140e343d3e222409373
c3130240b353e3f2e140d333a3d2224064445423024084247403e140a40494e2124074346413f140941484f2d14054f3a4d2924025b415f3e24035052544c240
55e44524a24015c46504d24045f43534b24065d455144260435363738333f340a617072734408637e64714406657c66744409647f61724407667d63704405627
b6574440a6d7c7e7244086f7a708044066188728344096e7b7f7144076089718f340562877d7b440779838a80540c7a888b8e440a7c868d8c44087e84898f440
b7b878c8d44097d858e86460b607f6e6d6c69306080808f9680a0808080806080608080a0836d848081677080638364847d94847d9d84808d8360887f9080a08
08080608080a0a0808060808e88619e88919560819b9081927891927861909460809c9080608080a080807c908074608278617e88617e88917460817c9081727
891708080a278619278919b90819560819e88919e8861907460807c9080a080806080809c908094608e88617278617278917c90817460817e8891708080aa930
1000102000204000403000703000408000807000507000806000605000105000602000019000f0b000a0f000b09000d0c000e0b000a0c00001c00090d000e0d0
00a0400001700030c000f00100a0e00080f00021111041211031411011311051610061810081710071510091a100a1c100c1b100b1910071b10091510061a100
c18100e1d100f1e10002f100120200221200d1220042320052420062520072620082720032820022820032d100026200721200e1420052f100a29200b2a200c2
b200d2c200e2d20092e200d19200e2220012d200c20200f1b200a2e10003f200130300231300332300433300f24300a20300f2920043e200d2330023c200b213
00635310736310837310938310a3931053a31063a210e2a31093d21073b210c3b310e3c310d3e310b3d31004f300140400241400342400443400f34400645400
746400847400948400a4940054a40044a40054f300248400943400046400741400c4b400d4c400e4d400f4e40005f400b40500f3b40005440034f400e4240014
d400c40400251500352500453500554500655500156500c4250015b400650500f4550045e400d43500857510958510a59510b5a510c5b51075c51085c41005c5
10b5f41095d410f5d510e506104071a121a110b77ab7087a8708ba8708ca9708baa708bab708ba87083b88083bb8084ba8084b98084b88080b88080bb808b9e8
08a90808f908080a38084a38085a0808aa08085ae808e9e80879a80879080829080829a808b8a808b8a808b89808d87808e85808e84808f83808e81808d81808
b80808f70808f7480888480888580888580868880858a80858c80858d80868e80878e808ba0808bae8084be8087bd8087b78085b68086b4808db4808db08084b
08080b58080b08088bb8088b8808dba7088ba7087ba7087b97089b7708bb5708bb4708bb3708bb1708ab17088b0708ca07084b47085b57085b57082b87081ba7
081bc7082bd7083be7084be708dbe7082a07082ae708bae708ead7080bb7080b9708ea7708ca6708da47087a57087a070899b708795708b95708d9e7081a0708
c90708b93708793708690708a8670888070848070809070859e70848e70868870888e708c8e708e88708f8e708c807082ab8080a58084a580819070869e708f7
e708b9a8080000b7307010506010405010304010102010207010601010a09010d08010c0b010e0d01090e010b0a010c08010d3e31052621091a110a1b1106171
10b1c110627210e35310819110728210829210615110514110e2f210413110021210312110c2d210f1021092a210e1f110f20310710110211110d2e210b78110
a2b210b2c210f00310d1e110c1d110425210324210223210122210637310b3c31013c31073831083931093a310132310a3b310233310536310334310a4e51055
f510e5f510344410f30410243410d4e410f34510657510e4f410142410c5d51094a410354510445410041410556510d5b41095a510a5b510859510758510b5c5
__map__
014c4d014b4c015253015152015051014f50014849014748014647014546016162016566017677017172016465017273017071016364016667016e6f016768016f70016b7a016a6b01696a016c6d016061017576016062017577017a6e016974017978016379016d73016c74016878011110010f7b01343d01061f201d1d101f
010c869a8d869a967a9a8d7a9a969080909080707080707080908da08d8da07973a07973a08d050904090b0a080604030d08060804070e0b0c070405060a0e08040c090d040580a080a083806083808088618083a00e020101040301050600050800060700060a00070800090a00090c000a0b000b0c00080c00050900070b00
071f1d10190e1303060ba060b0a060706060706060b0a080b0a080706080706080b07660b0a07370a07386000007010201030401050601070801040901060a010a0b01042110191f01188080a0698097608080698069808060978069a080809780978093967093906a938070937080936a90937096938090939080869075868b
7086807586758086708b86759086808b868b100804120f11070604140d13050404160b15030204180917010104171012080704110e14060504130c16040304150a18020c04221b210b0a04241923090904232025100f04271e260e0d04281c220c0b04211a240a1004251f270f0e04261d280d109b8d8b8b8d65658d75758d9b
8b8d9b9b8d75758d65658d8b9b8e8b8b8e65758e65658e8b8b8e9b9b8e75658e75758e9b280201000302000403000504000605000706000807000108000a09000b0a000c0b000d0c000e0d000f0e00100f00091000070f00100800050d000e0600030b000c04000109000a020012110013120014130015140016150017160018
17001118000b1300140c00091100120a001018000e1600170f00150d000718110c170e1a190367b37cb7b378afb378a1b87fb7bc7dafbc7d9db884b7bc86afbc869db387b7b38bafb38ba1af84b7ab86afab86a8af7fb7ab7dafab7da8ab84a8b47d99968a8dab84a8a78691a0869e6987a36287a35d8ca35d92a36297a36997
a36d92a36d8ca3658f9fab7da88986c77784e14884924884685d844a80843fa3844ab88468b884928984e1808c90778c8d718c85718c7b778c73808c70898c738f8c7b8f8c85898c8d77728d71728571727b7772738072708972738f727b8f728589728d807290777de1487d92487d685d7d4a807d3fa37d4ab87d68b87d9289
7de18979c77786c77779c7ab84a8b47d99b48499848b6b7c8b6b848a637c8a637c88578488577c895f84895f8c8b6e858b6b8f8a67888a648d885994885c8a89609189637b8b6b748b6e788a64718a676c885c7388596f8963768960390204010703060304020604050504030c080b0604040b090a080408110d10090409100e
0f0c040e1513140b040d1612150406071e1b16110c0f05131a182a190e04121b171a1204181d021c1104171e011d030320211c06031f20050c041429272509040f2528260f031924292e0a4445464748494a864b433f0a535251504f4e4d554c5424053b5e445f712d054b60745f432a0441614a6229044062496328043f6348
6427043e64476526043d65466625043c66455e49078384816753687541045c71787642055d766a556b4304566b4d6c4404576c4e6d4504586d4f6e4604596e506f47045a6f517048045b70526737056a7368544c4c047874777323047269757725043b5c5d7926043c79567a27043d7a577b28043e7b587c29043f7c597d2a04
407d5a7e2b04417e5b7f2c04808583694f04427f81820905268e8d1f0a53048988878a54049091928f5b04959493965c0498999a9763049d9c9b9e6404a0a1a29f16098b8c8661428e282724398f668c9064809e808ca080808f9a8c909c80709c80719a8c8080a060808062808c70648071668c6a6d73886571789d8b889c72
6c809980a0808060807b9f8380a083869f80859f7d82a07b7ea07b7b9f7d7a9f80866184a080807a61847861807a617c7e617982617986617c8861808060848080a060808065809160808066806d7680628a80629a806da080809b80919b80918f7f6480a07b80a07b82a07b82a07b7ea07b7ea07b859f83a201020002030004
05000506000306000502000104000708000809000609000805000407000a0b000b0c00090c000b0800070a000d0e000e0f000f0c000b0e000d0a00101100111200160f000e1100100d00031200110200011000061400031400141200131201130f01161800150c001709001815001517000f18001216001a19011b1a011c1b01
1d1c011e1d011f1e01201f011920011921011d2101211e011b2101211c01211a01202101211f012524002625002726002827002928002a29002b2a004f2b002e2d002f2e00302f003130003231003332003433003534002d3600403700383900393a003a3b003b3c003c3d003d3e003e3f003f40003738004243004344004445
00454600464700474800244100414200252f004b2e002336002b35002a3400293300283200273100263000483e004a3f002c49004c3700423800433900443a00453b00463c00473d00244b002c23004a4c004b2300494a00414c00234a004b4c002542002643002744002845002946002a47002b48002c4d00484e004f4e0022
49004e22004d2200363500505100525000535200515300162c002c36004f14004f17005654005455005557005756005859005a58005b5a00595b005e5c005c5d005d5f005f5e0060610062600063620061630066640064650065670067660009121019101d0c1f1a1d051c7a7a7a7a867a7a7a867a8686867a7a86867a867a86
8686867d838d7d7d8d837d8d83838d737d83737d7d73837d7383837d7d737d8373838373837d738d83838d7d838d7d7d8d837d80508a78507b88507b8090801902040319171a08040711101208040929272a06040c212022030405080b01080406030c090a040d0f100e070405130e11040406120f14030404140d130e041617
18150304011b151c0404041c18190104021a161b14041e201d1f05040a221e23020402241d2101040b231f241604252728260704072a252b06040a2c28290504082b262c190330312f1b0331322e1a0332302d19729d809d808e8e9d80809d7280608080a0808080a080638e809d8e63808e60808072638072809d7280638080
609d8072638072806372a080808e809d8e80638e63809c829080826064829032030100010200020400040300070300040800080700050700080600060500010500060200090a000b0a00090c000c0b00070b000c0800030a000904000d0e000e0f000f1000100d000410000f0200010e000d0300111200131400111400131200
0212001306001405000111001516001716001518001817000618001508001607000517001a19001b1a00191b001c19001b1c001a1c00051f1410230301428d79807379807280728e80727387808d87808e8088728088a17b80a18075a18580a180855f7b805f80755f85805f80858080907a868e768a88758b80768a787a8069
78808e7a7a8e76768875758076767880788e807288807080807278867a8e8a76888b75808a767886806988808e86868e8a8a888b8b808a8a7880888e808e88809080808e78808069939b8ca19098a1709893658c936560a17055a19055939b607a80599d80636380638680596d9b8c5f90985f70986d658c6d65605f70555f90
556d9b60300604060d0b0e0704070e0c0f0104030f0a1004040110090d0504081514160804041712150204021811170304051613182c04424b1b4a2a0349194c2d04434a1c4d2b04414c1a4b230331745513041a20251f2e04444573721203194e2008042526211e17034e4f261b04232b292a1904212d272c1a04222c282b18
034f502d1d0427332e321e0428322f351c035051331f042935303415044d44241d0304023f2336200351523a0304371c540521042e3a3e390204041e223f250352534024037356740504541b1f0807043e403b3824043134757228043c474246260353494829043d46434527043b484147040406573d56060407383c57010458
2f39030404553058011b047124752a160376371d160371367630839d728397968369968363727d97967d69967d63727d9d72749d887d889f749d787796966d93916a89967a689478839f6a7796787d9f746378776a967463887d789f896a968c638883789f8c637886689464727a887d9f648e7a96779663748888839f6d6d91
638c889689967a98948c9d8883889f8c9d788996969c8e7a9d8c889d74889c727a869894936d919393917a0401000302000107000802000503000604000607000805000a0900090c000b0a000b0c00040a000b06000c07000901000e0d00100d000f0e00100f000810000f0500020d00030e0011120012130013140014150015
1600190800081300121700181900191a001a1b00162e001708001718001c1d001d1e001e1f001f1b001a1e001d1900181c00202100212200222300232400211d001c20001f2300221e001b0300031500072700210700252000262700272800282900250700021a002625002a2b002b2c002c2d002e2d00292d002c2800272b00
2a2600112a00142c002b1300122a00152d00111700111800111c00112000112500112600051400230400042900062800012200302f013130013231013233012f36013433013534013635013035013134010e39010a3801373901383a013c3b013d3c013e3d013e3f013b4201403f014140014241013c41013d40011b1600242e
002924002404002e1f00031600162401373a013a240137160100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000800001a75021750000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200002c060350503b0403e0403365029060216501e0501665015040116400d0400b6300a030076300803007630060300463004030036300263002640016400164001640016300163001630016300163001620
000100003c5503875034550317502f5502b55025750245501f7501f5301a720185201171010550097500655004750047500175004550047500b50008500065000350001500015000000000000000000000000000
000200002866034670396703b6603a670376603667033660306702b670286701c660075701766007560166600656014660085601366007560106600a5600d6600556009660025600566002560046600156004660
000300002f3502f3502f3502f3502f3502f3503d3503d3503c3503c3503c350353503533035330353300e30012300163001a3001e3002330026300293002b3002f300284002630035400203001c300364001b300
000600002bc602fc702fc7029c603725036f5034c6032f7038f7038f6022350223401e3301c3302ff302ff4036f4035f402fc3031f5030c7036f702fc6038f402a33038350383603636020c5026c502ec5032c60
000300000d6500e650106501265015650186501c6501e650216502165021650206501d6501b650166501665013650126500f6500e6500c6500b65008650076500665005650046500465002650016500165001650
00030000263500d300173001c30026350000001c30000000263500000000000000001b30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100003925038250322502c250230501d2501c0501625012050107500b0500b75003050140500c750080500a750070500775007050057500505004050020500205001050010500420004200036000420004200
000300001a6500a750266500f75032650147502c650117502965010650186500e650186500d650176500b650166500e6501a6500e650146501a6500625014650062500d650047500d65001650056500265006650
000b0000067510276106771027710677101771067710276106761027610677101571067710257106761035610676101561067610276106761027710575102751057410c741147411d75116741107410b73108721
011000001815018150181501815018155181501815018150181501815018150181550000018150181501815018150181551815018150181550000018150000001815000000181501815018150000001815018150
011000001c1501c1501c15518150181501815018150181501815018155000001815018150181501815018155181501815018155000001c150000001c15000000181501415000000181501c1501c1501c1501c150
011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018150181501815018150
0110000018150181501815514150141501c1501c1501c1501c1501c1550000014150141501c1501c1501c1551415014150141550000018150000001815000000141501815000000141501f1501f1501f1501f150
011000001c15518150181501c1501c1501c1501c1501c1550000014150141501c1501c1501c15500000181501815018155181501815518150000001c150000001815018150000000000000000000000000000000
01100000181551c1501c1501815018150181501815018155000001c15018150181501815018155000001c1501c1501c1551c1501c1551c1501c1551c150000001c1501c150000000000000000000000000000000
01100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001815000000181501c1501d1501d1501d1501d1501d1501d150
011000001f15514150141501f1501f1501f1501f1501f15500000181501c1501f1501f1501f155000001415014150141551f150000001f150000001f150000001f1501f150111501115011150111501115011150
011000000000000000000000000000000000000000000000000000000000000000000000000000000000000014155000000000000000000000000000000000000000000000000000000000000000000000000000
011000001d1551f1501f1501f1501f1501f1501f15520150221502015020150201502015020150201502015020155181501815018150181501815518150181551d1501d1501d1501d1501d155000001f1501f150
01100000111551315013150131501315013150131551415016150141501415014150141501415014150141500c1500c1500c1500c1500c1500c1550c1500c1551115011150111501115011155000001315013155
011000001f15520155000000c15500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0110000020150181500000020150000001d140241502215022150221502215022150221502215022150221502215022155181501815018155181501d1501d1501d1501d1501d1501d155000001f1502015020150
0110000014150141550c1501415000000111501815016150161501615016150161501615016150161501615016150161550c1500c1500c1550c15011150111501115011150111501115500000131501415014150
011000000000000000000000000024155000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000000000000000000000018155000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01100000201551d15024150241502015029150291502915029150291502915029155000001d1501d1501d1501d155201501f1501d150241502415024150241502415500000201501d14018150181501815500000
011000001415511150181501815014150000001d1501d1501d1501d1501d1501d1501d1551115011150111501115514150131501115018150181501815018150181550000014150111500c1500c1500c15500000
011000000000000000000001d1501d1501d1501d1501d1501d1501d1501d1501d1550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000001815018155000001815000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000c1500c155000000c15011150111501115011150111501115011150111501115011150111550000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800002e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e145000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800002914029140291402914029140291402914029140291402914029145000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800002614026140261402614026140261402614026140261402614026145000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800000010000100001000010000100001000010000100001000010000100001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01080000000000000000000000002214022140221402214022140221451d1401d14500000271402714500000291402914527140271450000022140221450000022140221451d1401d14500000271402714500000
01080000291402914527140271450000022140221450000022140221451d1401d1450000027140271450000029140291452214000000221402214022145000001d1401d1451d1401d145000001d1401d14500000
010800000514005145031400314500000051400514500000081400814008140081400814008140081400814008140081400814008140081400814008145000000514005145051400514500000051400514500000
010800002214022140221402214022140221402214022140221402214022140221402214022140221450000029140291402914029140291402914029140291402914029140291402914029140291402914500000
010800000000000000000000000000000001400014000000001400014000140001400014000140001400014000140001450000000000001400014000140000000014000140001400014500140001400014000145
0108000027140271452614026145000002414024145000002e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1452914029140291402914029140291402914500000
010800000000000000000000000003140031400314003145000000000000000000000314003140031400314503140031450314000000031400314003145000000014000145001400014500000001400014500000
0108000027140271452614026145000002414024145000002e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1402e1452914029140291402914029140291402914029145
01080000271402714526140261450000027140271450000024140241402414024140241402414024140241402414024140241402414024140241402414024145000000000000000000001d1401d1401d14000000
010800002414024145231402314500000241402414500000211402114021140211402114021140211402114021140211402114021140211402114021140211450000000000000000000000000000000000000000
010800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000051400514005140000000514005145000000000005140051450000000000
010800000a1500a1500a1500a1500a1500a1500a15500000091500915009150091500915009150091500915009150091500915009155000000000009140091450a1500a1550a1400a14500000091400914500000
0108000007150071500715007150071500715007155000000715007150071500715500000000000f1400f1450f1500f1550e1500e155000000c1500c155000000a1500a155091500915500000071500715500000
01080000051500515005150051500515005150051550000007140071450000000000091400914500000000000a1500a155091400914500000071400714500000051500515500000000000a1400a1450000000000
010800002714027145261402614500000271402714500000241402414024140241402414024140241402414024140241402414024140241402414024140241450000000000000000000000000000000000000000
010800000514005145000000000000000000000000000000051500515505140051450000005140051450000005150051500515005150051500515005150051550000000000000000000000000000000000000000
010d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000025120000002512025120251202512525120
010d00003062500000000003062530625000000000030625000003062530625306253062530625000000000030625000003062500000000003062530625306253062521120000003062500000000003062530625
010d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003062500000211202112021120211251e120
010d00000b1200b125000000000000000000000000000000000000b1200b1200b1200b1200b12000000000000000000000000000000000000000000b1200b1200b120281200b1202812028120281202812522120
010d00002512500000251202812025120251202512025125221202212500000281202b1202b1202b1202b1202b1252712027125281202712021120000001e1201e1201e1201e1201e1201e1201e1201e1250b120
010d00000000000000211200000030625306253062530625306250000000000241203062524120241202412030625306253062530625306252812000000251202512030625306250000000000306253062530625
010d00001e1201e1253062500000281202812028125000002512025125000003062500000000000000000000241252a1202a125241202a1203062500000000000000025120251202512025120251202512025120
010d0000221250000028120211200b1200b1200b1200b1201e1201e125000002b1202412028120281202812028125231200b1202b12023120251200000022120221202212022120221202212022120221250b120
010d0000000000b120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010d00003062530625306250000000000000003062530625000000000030625306253062500000306253062530625000000000030625306250000000000000003062530625306253062530625000003062530625
010d0000000000b120000000b12000000000000000000000000000000000000000000b1200b1200b1200b1200b12000000000000000000000000000000000000000000b1200b1200b1200b120000000b1200b125
__music__
01 20212223
00 24404040
00 25482640
00 27402840
00 29402a40
00 2b6b2a40
00 2c2d2e40
00 27402f40
00 29403040
00 2b413140
02 322d3340
01 34353637
00 38393a3b
04 403d403e
01 0b534040
00 0c0d400e
00 0f101112
00 13401415
00 16401718
00 191a1b1c
04 1d401e1f
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000

