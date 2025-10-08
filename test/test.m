for k = 1:N_sim
    fprintf('\rTime step %d/%d (%.2f h)', k, N_sim, (k-1)*Ts);
    drawnow limitrate nocallbacks;  % zwingt MATLAB, den Text sofort zu zeigen
    pause(0.05);                    % nur zur Demo
end
fprintf('\n');
