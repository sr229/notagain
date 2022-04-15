local speed = 1
local threshold = 30

local roll_time = 0.75/speed
local roll_speed = 1*speed

local dodge_time = 0.5/speed
local dodge_speed = 1*speed

local function is_rolling(ply)
	if CLIENT and ply ~= LocalPlayer() then
		return ply:GetNW2Float("roll_time", CurTime()) > CurTime()
	end
	return ply.roll_time and ply.roll_time > CurTime()
end

local function is_dodging(ply)
	if CLIENT and ply ~= LocalPlayer() then
		return ply:GetNW2Float("dodge_time", CurTime()) > CurTime()
	end
	return ply.dodge_time and ply.dodge_time > CurTime()
end

jrpg.IsActorRolling = is_rolling
jrpg.IsActorDodging = is_dodging

local function vel_to_dir(ang, vel, speed)
	ang.p = 0
	local dot = ang:Forward():Dot(vel)
	if dot > 100*speed then
		return "forward"
	elseif dot < -100*speed then
		return "backward"
	end

	local dot = ang:Right():Dot(vel)
	if dot > 0 then
		return "right"
	else
		return "left"
	end
end

if SERVER then
	util.AddNetworkString("roll")

	hook.Add("EntityTakeDamage", "roll", function(ent, dmginfo)
		if (is_rolling(ent) or is_dodging(ent)) and (bit.band(dmginfo:GetDamageType(), DMG_CRUSH) > 0 or bit.band(dmginfo:GetDamageType(), DMG_SLASH) > 0) then
			dmginfo:ScaleDamage(0)
			ent:ChatPrint("dodge!")
			return true
		end
	end)
end

if CLIENT then
	hook.Add("CalcView", "roll", function(ply, pos, ang)
		if (is_rolling(ply) or is_dodging(ply)) and ply:Alive() and not ply:InVehicle() and not ply:ShouldDrawLocalPlayer() then
			local eyes = ply:GetAttachment(ply:LookupAttachment("eyes"))

			return {
				origin = eyes.Pos,
				angles = eyes.Ang,
			}
		end
	end)

	hook.Add("CalcViewModelView", "roll", function(wep, viewmodel, oldEyePos, oldEyeAngles, eyePos, eyeAngles)
		if not wep or not wep:IsValid() then return end
		local ply = LocalPlayer()

		if (is_rolling(ply) or is_dodging(ply)) and ply:Alive() and not ply:InVehicle() and not ply:ShouldDrawLocalPlayer() then
			local eyes = ply:GetAttachment(ply:LookupAttachment("eyes"))

			return eyes.Pos, eyes.Ang
		end
	end)
end

local function can_roll(ply)
	if jrpg.IsWieldingShield(ply) then return end
	return (ply:IsValid() and jrpg.IsEnabled(ply) and not is_rolling(ply) and ply:Alive() and ply:OnGround() and ply:GetMoveType() == MOVETYPE_WALK and not ply:InVehicle()) or ply.roll_landed
end

local function can_dodge(ply)
	return (ply:IsValid() and jrpg.IsEnabled(ply) and not is_dodging(ply) and ply:Alive() and ply:OnGround() and ply:GetMoveType() == MOVETYPE_WALK and not ply:InVehicle())
end

hook.Add("UpdateAnimation", "roll", function(ply, velocity)
	if is_dodging(ply) then
		local dir = vel_to_dir(ply:EyeAngles(), velocity, dodge_speed)
		if dir == "forward" or dir == "backward" then
			ply.dodge_back_cycle = (ply.dodge_back_cycle or 0) + FrameTime() * 1.25

			ply.dodge_fraction = math.Clamp(ply.dodge_back_cycle,0,1)

			if ply.dodge_fraction < 1 then

				local f = ply.dodge_fraction
				--f = math.EaseInOut(f, 1, 2)

				if dir == "forward" then
					local cycle = Lerp(f, 0.7, 0.25)
					if cycle <= 0.3 then cycle = 0.68 end
					ply:SetCycle(cycle)
				elseif dir == "backward" then
					ply:SetCycle(Lerp(f, 0.25, 0.7))
				end

				ply:SetPlaybackRate(0)

				return true
			end
		end
	else
		ply.dodge_back_cycle = nil
		ply.dodge_fraction = nil
	end

	if is_rolling(ply) then
		local dir = vel_to_dir(ply:EyeAngles(), velocity, roll_speed)

		if dir == "forward" or dir == "backward" then
			ply.roll_back_cycle = (ply.roll_back_cycle or 0) + (ply:GetVelocity():Length2D() * FrameTime() / 200)
		else
			ply.roll_back_cycle = (ply.roll_back_cycle or 0) + (ply:GetVelocity():Length2D() * FrameTime() / 200)
		end

		ply.roll_fraction = math.Clamp(ply.roll_back_cycle,0,1)

		if ply.roll_fraction < 1 then

			local f = ply.roll_fraction
			--f = math.EaseInOut(f, 1, 2)

			if dir == "forward" then
				ply:SetCycle(Lerp(f, 0.1, 0.9))
			elseif dir == "backward" then
				local cycle = Lerp(f, 0.9, 0)
				if cycle < 0.05 then cycle = 1 end
				ply:SetCycle(cycle)
			elseif dir == "left" or dir == "right" then
				ply:SetCycle(Lerp(f, 0, 1))
			end

			ply:SetPlaybackRate(0)

			return true
		end
	else
		ply.roll_back_cycle = nil
		ply.roll_fraction = nil
	end
end)

hook.Add("OnPlayerHitGround", "roll", function(ply)
	if jrpg.IsEnabled(ply) and ply:KeyDown(IN_DUCK) then
		ply.roll_landed = true
		ply.roll_ang = ply:GetVelocity():Angle()
	end
end)

hook.Add("CalcMainActivity", "roll", function(ply)
	if is_rolling(ply) and ply.roll_fraction and ply.roll_fraction < 1 then
		local dir = vel_to_dir(ply:EyeAngles(), ply:GetVelocity(), roll_speed)

		local seq = ""

		if dir == "forward" or dir == "backward" then
			seq = "wos_bs_shared_recover_forward"
		elseif dir == "left" then
			seq = "wos_bs_shared_recover_left"
		elseif dir == "right" then
			seq = "wos_bs_shared_recover_right"
		end

		local seqid = ply:LookupSequence(seq)

		if seqid > 1 then
			return seqid, seqid
		end
	end

	if is_dodging(ply) and ply.dodge_fraction and ply.dodge_fraction < 1 then
		local dir = vel_to_dir(ply:EyeAngles(), ply:GetVelocity(), dodge_speed)

		local seq = "ws_bs_shared_roll_backward"

		if dir == "left" then
			---seq = "pure_b_s2_t1"
		elseif dir == "right" then
		--	seq = "pure_b_s2_t1"
		end


		local seqid = ply:LookupSequence(seq)

		if seqid > 1 then
			return seqid, seqid
		end
	end
end)

hook.Add("Move", "roll", function(ply, mv, ucmd)
	if not jrpg.IsEnabled(ply) then return end

	if mv:GetVelocity():Length2D() < threshold then
		ply.roll_ang = nil
		ply.roll_time = nil
		ply.roll_time2 = nil
		ply.roll_dir = nil
		ply:SetNW2Float("roll_time", 0)
		ply:SetNW2Float("roll_time2", 0)

		ply.dodge_ang = nil
		ply.dodge_time = nil
		ply.dodge_time2 = nil
		ply.dodge_dir = nil
		ply:SetNW2Float("dodge_time", 0)
		ply:SetNW2Float("dodge_time2", 0)

		return
	end

	if can_dodge(ply) then

		if mv:KeyPressed(IN_JUMP) then

			if jtarget.GetEntity(ply):IsValid() and mv:KeyDown(IN_JUMP) then
				ply.dodge_ang = mv:GetAngles()

				ply.dodge_time2 = dodge_time / math.Clamp(mv:GetVelocity():Length2D() / 200, 0.75, 1.25)
				ply.dodge_time = CurTime() + ply.dodge_time2
			end

			if ply.dodge_time then
				if mv:GetForwardSpeed() > 0 then
					ply.dodge_dir = "forward"
				elseif mv:GetForwardSpeed() < 0 then
					ply.dodge_dir = "backward"
				end

				if not ply.dodge_dir then
					if mv:GetSideSpeed() > 0 then
						ply.dodge_dir = "right"
					else
						ply.dodge_dir = "left"
					end
				end

				ply:AnimRestartMainSequence()

				if SERVER then
					ply:SetNW2Float("dodge_time", ply.dodge_time)
					ply:SetNW2Float("dodge_time2", ply.dodge_time2)

					jattributes.SetStamina(ply, math.max(jattributes.GetStamina(ply) - 40, 0))

					ply:EmitSound("npc/zombie/foot_slide3.wav", 70, 100)
				end
			end
		else
			ply.dodge_ang = nil
			ply.dodge_time = nil
			ply.dodge_time2 = nil
			ply.dodge_dir = nil
		end
	end

	if can_roll(ply) then

		if mv:KeyPressed(IN_DUCK) or ply.roll_landed then
			if ply.roll_landed then
				local vel = mv:GetVelocity()
				local forward = ply:GetForward():Dot(vel)
				local right = ply:GetRight():Dot(vel)

				if math.abs(right) > math.abs(forward) then
					forward = 0
				else
					right = 0
				end

				mv:SetForwardSpeed(forward)
				mv:SetSideSpeed(right)
			end

			if mv:KeyDown(IN_BACK) or mv:KeyDown(IN_MOVELEFT) or mv:KeyDown(IN_MOVERIGHT) or mv:KeyDown(IN_FORWARD) or ply.roll_landed then
				ply.roll_ang = mv:GetAngles()

				ply.roll_time2 = roll_time / math.Clamp(mv:GetVelocity():Length2D() / 200, 0.75, 1.25)
				ply.roll_time = CurTime() + ply.roll_time2
			end

			ply.roll_landed = nil

			if ply.roll_time then
				if mv:GetForwardSpeed() > 0 then
					ply.roll_dir = "forward"
				elseif mv:GetForwardSpeed() < 0 then
					ply.roll_dir = "backward"
				end

				if not ply.roll_dir then
					if mv:GetSideSpeed() > 0 then
						ply.roll_dir = "right"
					else
						ply.roll_dir = "left"
					end
				end

				ply:AnimRestartMainSequence()

				if SERVER then
					ply:SetNW2Float("roll_time", ply.roll_time)
					ply:SetNW2Float("roll_time2", ply.roll_time2)

					jattributes.SetStamina(ply, math.max(jattributes.GetStamina(ply) - 30, 0))

					ply:EmitSound("npc/zombie/foot_slide3.wav")
				end
			end
		else
			ply.roll_ang = nil
			ply.roll_time = nil
			ply.roll_time2 = nil
			ply.roll_dir = nil
		end
	end

	if is_dodging(ply) and mv:GetVelocity():Length2D() > 30 then
		local dir

		local ang = ply.dodge_ang * 1
		ang.p = 0

		local dir = ply.dodge_dir
		local f = math.Clamp((ply.dodge_time - CurTime()) * (1/ply:GetNW2Float("dodge_time2")), 0, 1)

		local mult = (math.sin(f*math.pi) + 0.5) * dodge_speed

		mv:SetMaxSpeed(200*mult)
		mv:SetMaxClientSpeed(200*mult)

		if dir == "forward" then
			mv:SetForwardSpeed(10000)
		elseif dir == "backward" then
			mv:SetForwardSpeed(-10000)
		elseif dir == "left" then
			mv:SetSideSpeed(-10000)
		elseif dir == "right" then
			mv:SetSideSpeed(10000)
		end
	else
		ply.dodge_forward_speed = nil
		ply.dodge_side_speed = nil
	end

	if is_rolling(ply) and mv:GetVelocity():Length2D() > 30 then
		local dir

		local ang = ply.roll_ang * 1
		ang.p = 0

		local dir = ply.roll_dir
		local f = math.Clamp((ply.roll_time - CurTime()) * (1/ply:GetNW2Float("roll_time2")), 0, 1)

		local mult = (math.sin(f*math.pi) + 0.5) * roll_speed

		mv:SetMaxSpeed(200*mult)
		mv:SetMaxClientSpeed(200*mult)

		if dir == "forward" then
			mv:SetForwardSpeed(10000)
		elseif dir == "backward" then
			mv:SetForwardSpeed(-10000)
		elseif dir == "left" then
			mv:SetSideSpeed(-10000)
		elseif dir == "right" then
			mv:SetSideSpeed(10000)
		end
	else
		ply.roll_forward_speed = nil
		ply.roll_side_speed = nil
	end
end)


