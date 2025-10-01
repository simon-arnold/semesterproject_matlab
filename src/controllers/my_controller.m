function u = my_controller(x, ref)
    Kp = 1.0;
    u = Kp * (ref - x);
end
