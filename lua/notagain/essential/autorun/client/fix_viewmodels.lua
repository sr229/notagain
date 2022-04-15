-- HACK: This one is meant to undraw viewmodels on death
-- as there's a nasty bug that prevents viewmodels to disappear
-- on the deathcam.
hook.Add("PostPlayerDeath", "fix_viewmodels", function(ply)
    ply:DrawViewModel(false)
end)