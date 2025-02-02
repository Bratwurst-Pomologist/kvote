local target = {}
local vote = {}
local voters = {}
local votes = {
  yes = 0,
  no = 0,
}
local kvote_in_progress = false
local hud_ids = {}
local vote_end_time = 0

local function reset_votes()
  votes.yes = 0 
  votes.no = 0 
  voters = {}
  hud_ids = {}
  target = {}
end

local function update_hud(player, target_name)
  local target_hud = target_name
  local remaining_time = math.max(0, math.floor(vote_end_time - os.time()))
  local online_players = minetest.get_connected_players()
  local amount_online_players = #online_players
  local hud_text = string.format("Kick vote for %s \n2/3 majority of all players is necessary to pass.\nVote status: Yea: %d Nah: %d\ntime left: %d s online players: %d", target_hud, votes.yes, votes.no, remaining_time, amount_online_players)
  local hud_id = hud_ids[player:get_player_name()]
  
  if hud_id then
    player:hud_change(hud_id, "text", hud_text)
  else
    hud_id = player:hud_add({
      hud_elem_type = "text",
      position = {x=0.7, y=0.1},
      offset = {x=0, y=0},
      text = hud_text,
      alignment = {x=1, y=0},
      scale = {x=100, y=100},
      number = 0xFFFFFF,
    })
    hud_ids[player:get_player_name()] = hud_id
  end
end

local function update_all_huds()
  if not kvote_in_progress then return end
  local target_name = target[next(target)]
  for _, player in ipairs(minetest.get_connected_players()) do
    update_hud(player, target_name)
  end 
  minetest.after(1, update_all_huds)
end

vote.new_vote = function(name, def, param)
  if kvote_in_progress then
    minetest.chat_send_player(name, "A vote is already running!")
    return
  end 
  kvote_in_progress = true
  vote_end_time = os.time() + def.duration
  minetest.chat_send_all(name .. " " .. def.descrip .. def.target .. " /ky for yes, /kn for no.")
  minetest.chat_send_all("A 2/3 majority of all players is necessary to pass.")
  reset_votes()
  target[name] = param
  local target_name = target[next(target)]
  for _, player in ipairs(minetest.get_connected_players()) do
    update_hud(player, target_name)
  end 
  update_all_huds()
  minetest.after(def.duration, function()
    if not kvote_in_progress then return end
    kvote_in_progress = false
    local total_votes = votes.yes + votes.no
    minetest.chat_send_all("Vote is finished. Yes: " .. votes.yes .. " No: " .. votes.no .. " total: " .. total_votes)
    local players = minetest.get_connected_players()
    local amount_players = #players
    local seventy_five_players = math.floor(amount_players * 0.75)
    local percentage_yes = math.floor((votes.yes / amount_players) * 10000 + 0.5) / 100
    if votes.yes > votes.no and votes.yes >= seventy_five_players then
      minetest.chat_send_all("Vote has been passed successfully with " .. percentage_yes .. "%.")
      local player_to_kick = minetest.get_player_by_name(param)
      if player_to_kick then
        minetest.kick_player(param, "You have been kicked by vote.")
        return true, param .. " has been kicked by vote."
        else
          return false, param .. " could not be found."
      end 
    else
      minetest.chat_send_all("No majority was found. Vote failed with " .. percentage_yes .. "%.")
    end
    for _, player in ipairs(minetest.get_connected_players()) do
      local hud_id = hud_ids[player:get_player_name()]
      if hud_id then
        player:hud_remove(hud_id)
        hud_ids[player:get_player_name()] = nil
      end
    end
  end)
end

local function has_voted(name)
  return voters[name] ~= nil
end

minetest.register_chatcommand("kvote", {
  description = "Initinate a vote to kick somebody",
  privs = {interact = true},
  params = "<playername>",
  func = function(name, param)
    local user = minetest.get_player_by_name(name)
	if not user then
		return false, "You can't use /kvote from IRC/Discord!"
	end
	local player = minetest.get_player_by_name(param)
	if not player then
		return false, "Target player is not online"
	end
	  target[name] = param
	  local target_name = target[next(target)]
    vote.new_vote(name, {
      descrip = "has started a kick vote for ",
      target = param,
      duration = 60,
    }, param)
    votes.yes = votes.yes + 1 
    voters[name] = true
    for _, player in ipairs(minetest.get_connected_players()) do 
      update_hud(player, target_name)
    end
  end,
}) 

minetest.register_on_joinplayer(function(player)
  local target_name = target[next(target)]
  if kvote_in_progress then
    update_hud(player, target_name)
  end
end)

minetest.register_chatcommand("ky", {
  description = "Vote with yes while day vote.",
  func = function(name)
    if not kvote_in_progress then
      minetest.chat_send_player(name, "There is no vote running right now.")
      return
    end
    if has_voted(name) then
      minetest.chat_send_player(name, "You have already voted.")
      return
    end
    votes.yes = votes.yes + 1 
    voters[name] = true
    minetest.chat_send_player(name, "you voted yes.")
    local target_name = target[next(target)]
    for _, player in ipairs(minetest.get_connected_players()) do 
      update_hud(player, target_name)
    end
  end,
})

minetest.register_chatcommand("kn",{
  description = "Vote with no while day vote.",
  func = function(name)
    if not kvote_in_progress then
      minetest.chat_send_player(name, "There is no vote running right now.")
      return
    end
    if has_voted(name) then
      minetest.chat_send_player(name, "you have already voted.")
      return
    end
    votes.no = votes.no + 1
    voters[name] = true
    minetest.chat_send_player(name, "You voted no.")
    local target_name = target[next(target)]
    for _, player in ipairs(minetest.get_connected_players()) do 
      update_hud(player, target_name)
    end
    return
  end,
})

minetest.register_chatcommand("kabort",{
  description = "Abort kick vote.",
  privs = {kick = true},
  func = function(name)
    if not kvote_in_progress then
      return false, "There is no kick vote running."
    end
    local players = minetest.get_connected_players()
    for _, player in ipairs(minetest.get_connected_players()) do
      local hud_id = hud_ids[player:get_player_name()]
      if hud_id then
        player:hud_remove(hud_id)
        hud_ids[player:get_player_name()] = nil
      end
      end
      kvote_in_progress = false
      reset_votes()
      minetest.chat_send_all("Kick vote has been aborted by " .. name .. ".")
end,})

minetest.register_chatcommand("kforcing",{
  description = "Forcing a positive kick result as presidential decree.",
  privs = {kick = true},
  func = function(name)
    if not kvote_in_progress then
      return false, "There is no kick vote running."
    end
    
    local target_name = target[next(target)]
    local player_to_kick = minetest.get_player_by_name(target_name)
    
    if player_to_kick then
     for _, player in ipairs(minetest.get_connected_players()) do
      local hud_id = hud_ids[player:get_player_name()]
      if hud_id then
        player:hud_remove(hud_id)
        hud_ids[player:get_player_name()] = nil
        --minetest.kick_player(target_name, "You have been kicked by presidential decree.")
        minetest.chat_send_all(name .. " has forced an positive vote result per presidential decree.")
        minetest.chat_send_all(target_name .. " has been kicked.")
        kvote_in_progress = false
        reset_votes()
        end
      end
    else
      return false, target_name .. " could not be found."
    end 
end,})