# A julia implementation of various algorithms from BCM17
# Written by Martin S. Copenhaver (www.mit.edu/~mcopen)


##########################
## Import packages    ##
##########################

using JuMP


##################################
## Auxiliary functions          ##
##################################

function aux_lassobeta(n::Int,p::Int,k::Int,mu::Float64,lambda::Float64,XX::Array{Float64,2},loc_b_c::Array{Float64,1},grad_rest::Array{Float64,1},max_iters=10000,tol=1e-3)
  # solve subproblem wrt beta, with (outer) beta as starting point

  MAX_ITERS = max_iters;
  TOL = tol;

  lbc = copy(loc_b_c);
  lbp = loc_b_c - ones(p);
  tcur = 1./norm(XX);
  iterl = 0;

  while (iterl < MAX_ITERS) && ( norm(lbc - lbp) > TOL )

    lbp = lbc;

    gg = lbc - tcur*(XX*lbc + grad_rest);

    lbc = sign(gg).*max(abs(gg)-tcur*(mu+lambda)*ones(p),zeros(p));

    #tcur = TAU*tcur;

    iterl = iterl + 1;

  end

  return(lbc);
end

function aux_admmwrtbeta(n::Int,p::Int,k::Int,mu::Float64,lambda::Float64,XX::Array{Float64,2},loc_b_c::Array{Float64,1},grad_rest::Array{Float64,1},sigma,max_iters=10000,tol=1e-3)
  # solve subproblem wrt beta, with (outer) beta as starting point

  MAX_ITERS = max_iters;
  TOL = tol;
  SIGMA = sigma;

  lbc = copy(loc_b_c);
  lbp = loc_b_c - ones(p);
  tcur = 1./norm(XX+SIGMA*eye(p));
  iterl = 0;

  while (iterl < MAX_ITERS) && ( norm(lbc - lbp) > TOL )

    lbp = lbc;

    gg = lbc - tcur*((XX+SIGMA*eye(p))*lbc + grad_rest);

    lbc = sign(gg).*max(abs(gg)-tcur*mu*ones(p),zeros(p));

    #tcur = TAU*tcur;

    iterl = iterl + 1;

  end

  return(lbc);
end



##################################
## Exact methods (MIO-based)    ##
##################################

### SOS-1 formulation

function tl_exact(p,k,y,X,mu,lambda,solver)
  #####

  # Inputs (required arguments):
  #    data matrix `X` and response `y`
  #    `p` is the number of columns of X (i.e., the number of features).
  #    `k` is the sparsity parameter on the trimmed Lasso
  #    `mu` is the multipler on the usual Lasso penalty: mu*sum_i |beta_i|
  #    `lambda` is the multipler on the trimmed Lasso penalty: lambda*sum_{i>k} |beta_{(i)}|
  #    `solver` is the desired mixed integer optimization solver. This should have SOS-1 capabilities (will return error otherwise).
  #    `bigM` is an upper bound on the largest magnitude entry of beta. if the constraint |beta_i|<= bigM is binding at optimality, an error will be thrown, as this could mean that the value of `bigM` given may have been too small.
  
  # Output: estimator beta that is optimal to the problem
  #         minimize_β    0.5*norm(y-X*β)^2 + μ*sum_i |β_i| + λ*T_k(β)

  # Method: exact approach using SOS-1 constraints and mixed integer optimization (e.g. using commercial solver Gurobi)

  #####  
 
  if ( p != size(X)[2] )
    println("Specified p is not equal to row dimension of X. Halting execution.");
    return;
  end

  m = Model(solver = solver);

  @variable(m, gamma[1:p] >= 0);
  @variable(m, beta[1:p] );
  @variable(m, z[1:p], Bin);
  @variable(m, pi[1:p] >= 0);

  @constraint(m, gamma[i=1:p] .>= beta[i] );
  @constraint(m, gamma[i=1:p] .>= -beta[i] );
  @constraint(m, sum(z) == p - k );
  @constraint(m, pi .<= gamma );

  # add SOS-1 constraints to the model; if the solver supplied does not support SOS-1 constraints, JuMP will throw an error; we do not catch that here so it will raise to the user
  for i=1:p
    addSOS1(m, [z[i],pi[i]]);
  end

  # add quadratic objective; again, if the solver cannot handle such an objective, an error will be raised
  @objective(m, Min, dot(beta,.5*X'*X*beta) - dot(y,X*beta)+dot(y,y)/2
   + (mu+lambda)*sum(gamma)-lambda*sum(pi) )

  solve(m);

  return getvalue(beta);

end


### big-M formulation

function tl_exact_bigM(p,k,y,X,mu,lambda,solver,bigM,throwbinding=true)
  #####

  # Inputs (required arguments):
  #    data matrix `X` and response `y`
  #    `p` is the number of columns of X (i.e., the number of features).
  #    `k` is the sparsity parameter on the trimmed Lasso
  #    `mu` is the multipler on the usual Lasso penalty: mu*sum_i |beta_i|
  #    `lambda` is the multipler on the trimmed Lasso penalty: lambda*sum_{i>k} |beta_{(i)}|
  #    `solver` is the desired mixed integer optimization solver. This should have SOS-1 capabilities (will return error otherwise).
  #    `bigM` is an upper bound on the largest magnitude entry of beta. if the constraint |beta_i|<= bigM is binding at optimality, an error will be thrown, as this could mean that the value of `bigM` given may have been too small.
  
  # Optional arguments:
  #    `throwbinding`---default value of `true`. To disable the built-in error functionality that occurs when the `bigM` value is potentially too small, set `throwbinding=false`.

  # Output: estimator beta that is optimal to the problem
  #         minimize_β    0.5*norm(y-X*β)^2 + μ*sum_i |β_i| + λ*T_k(β)

  # Method: exact approach using bigM constraints and mixed integer optimization (e.g. using commercial solver Gurobi)
  # Because bigM formulations are more easily used by solvers, this approach is much easier to use if you have a specific preference on which solver you use. However, note that the performance of this approach, much like the performance of solvers for any big-M-based optimization problem, is highly dependent upon tuning of the value of M. Therefore, if you do not have a good sense of what value to set for M and you have access to a solver that handles SOS-1 constraints, we recommend using the SOS-1-based approach (given in function tl_exact )

  #####  

  if ( p != size(X)[2] )
    println("Specified p is not equal to row dimension of X. Halting execution.");
    return;
  end

  if !( bigM >= 0 && bigM < Inf )
    println("Invalid big-M value supplied. Halting execution.");
  end

  m = Model(solver = solver);

  @variable(m, gamma[1:p] >= 0);
  @variable(m, a[1:p] >= 0);
  @variable(m, beta[1:p] );
  @variable(m, z[1:p], Bin);

  @constraint(m, gamma[i=1:p] .>= beta[i] );
  @constraint(m, gamma[i=1:p] .>= -beta[i] );
  @constraint(m, a[i=1:p] .>= bigM*z[i] + gamma[i] - bigM );
  @constraint(m, beta[1:p] .<= bigM );
  @constraint(m, beta[1:p] .>= -bigM );
  @constraint(m, sum(z[i] for i=1:p) == p - k );

  @objective(m, Min, dot(beta,.5*X'*X*beta) - dot(y,X*beta)+dot(y,y)/2
   + sum{mu*gamma[i]+lambda*a[i], i=1:p})

  solve(m);

  binding = false;

  for i=1:p 
    if abs(getvalue(beta[i])) >= bigM - 1e-3
      binding = true
    end
  end

  if (binding && throwbinding)
    println("\t\tWarning: big-M constraint is binding  -- you should increase big-M and resolve. Otherwise, re-use same big-M and set optional argument `throwbinding=false`.");;
  else
    return getvalue(beta);
  end
end


##################################
## Heuristic (convex) methods   ##
##################################


### alternating minimization

function tl_apx_altmin(p,k,y,X,mu,lambda,lassosolver=aux_lassobeta,max_iter=10000,rel_tol=1e-6,print_every=200)

  #####

  # This is known as Algorithm 1 in the paper BCM17 (using difference-of-convex optimization)

  # Inputs:
  #    data matrix `X` and response `y`
  #    `p` is the number of columns of X (i.e., the number of features).
  #    `mu` is the multipler on the usual Lasso penalty: mu*sum_i |beta_i|
  #    `lambda` is the multipler on the trimmed Lasso penalty: lambda*sum_{i>k} |beta_{(i)}|
  #    `solver` is the desired mixed integer optimization solver. This should have SOS-1 capabilities (will return error otherwise).
  #    `bigM` is an upper bound on the largest magnitude entry of beta. if the constraint |beta_i|<= bigM is binding at optimality, an error will be thrown, as this could mean that the value of `bigM` given may have been too small.
  
  # Optional arguments:
  #    `lassosolver`---default value of `aux_lassobeta`, which is a simple Lasso problem solver whose implementation is included above as an auxiliary function. If you would like to solve the Lasso subproblems using your own Lasso solver, you should change this argument. Note that the `lassosolver` values expect as function which has the following characteristics:
  ##                 Intput arguments will be as follows: `n` - dimension of row size of `X`;
  ##                                                      `p` - as in outer problem;
  ##                                                      `k` - as in outer problem;
  ##                                                      `mu` - as in outer problem;
  ##                                                      `lambda` - as in outer problem;
  ##                                                      `XX` - value of transpose(X)*X (can be precomputed and stored offline);
  ##                                                      `loc_b_c` - initial value of beta from which to initial the algorithm;
  ##                                                      `grad_rest` - the remaining part of the gradient term (-X'*y- gamma).
  ##                  Output: solution beta to the Lasso problem
  ##                          minimize_beta norm(y−X*beta)^2 +(mu+lambda)*sum_i |beta_i| − dot(beta,gamma) (gamma is the solution from the alternating problem, as supplied in the additional gradient information).
  #    `max_iter`---default value of 10000. Maximum number of alternating iterations for the algorithm.
  #    `rel_tol`---default value of 1e-6. The algorithm concludes when the relative improvement (current_objective-previous_objective)/(previous_objective + .01) is less than `rel_tol`. The additional `0.01` in the denominator ensures no numerical issues.
  #    `print_every`---default value of 200. Controls amount of amount output. Set `print_every=Inf` to suppress output.


  # Output: estimator beta that is a *possible* solution for the problem
  #         minimize_β    0.5*norm(y-X*β)^2 + μ*sum_i |β_i| + λ*T_k(β)

  # Method: alternating minimization approach which finds heuristic solutions to the trimmed Lasso problem. See details in Algorithm 1 in BCM17.

  #####  

  AM_ITER = max_iter;
  REL_TOL = rel_tol;
  PRINT_EVERY = print_every; # AM will print output on every (PRINT_EVERY)th iteration

  beta = randn(p);#starter;#zeros(p);
  gamma = zeros(p);#starter;#zeros(p);

  XpX = X'*X; # can separate computation if desired

  prev_norm = 0;
  prev_obj = 0;

  for I=0:AM_ITER

    # solve wrt gamma (by sorting beta)

    II = zeros(p);
    sto = 0; # number set to "one" (really += lambda)

    bk = sort(abs(beta))[p-k+1];

    for i=1:p
      if (abs(beta[i]) > bk)
        gamma[i] = lambda*sign(beta[i]);
        sto = sto + 1;
      else
        if (abs(beta[i]) < bk)
          gamma[i] = 0;
        else
          II[i] = 1;
        end
      end
    end

    if sum(II) == 0 
      println("ERROR!");
    else
      if sum(II) == 1
        gamma[indmax(II)] = lambda*sign(beta[indmax(II)]);
        sto = sto + 1;
      else # |II| >= 2, so need to use special cases as detailed in paper's appendix
        #println(II);
        if bk > 0
          j = indmax(II); # arbitrary one from II ---> should probably choose randomly amongst them
          if dot(X[:,j],X*beta-y) + (mu+lambda)*sign(beta[j]) != 0
            gamma[j] = 0;
          else
            gamma[j] = lambda*sign(beta[j]);
            sto = sto + 1;
          end
          # assign rest of gamma
          for i=randperm(p)
            if (sto < k) && (II[i] > 0.5)
              gamma[i] = sign(randn())*lambda; 
              sto = sto + 1;
            end
          end

        else # so bk == 0
          # need to check interval containment over indices in II
          notcontained = false;
          corrindex = -1;
          corrdot = Inf;
          for i=randperm(p)
            if II[i] > 0.5 # i.e. == 1
              dp = dot(X[:,i],X*beta - y);
              if (abs(dp) > mu)
                notcontained = true;
                corrindex = i;
                corrdot = dp;
                break;
              end
            end
          end

          if notcontained
            j = corrindex;
            if corrdot > mu
              gamma[j] = -lambda;
              sto = sto + 1;
            else
              gamma[j] = lambda;
              sto = sto + 1;
            end
            # fill in rest of gamma
            for i=randperm(p)
              if (sto < k) && (II[i] > 0.5) && (i != j)
                gamma[i] = sign(randn())*lambda; 
                sto = sto + 1;
              end
            end
          else # any extreme point will do
            for i=randperm(p)
              if (sto < k) && (II[i] > 0.5)
                gamma[i] = sign(randn())*lambda; 
                sto = sto + 1;
              end
            end
          end

        end
      end
    end

    # ensure that sto == k

    if sto != k
      println("ERROR. EXTREME POINT NOT FOUND. ABORTING.");
      # println(gamma);
      # println(sto);
      # println(II);
      # println(beta);
      II(1)
    end


    # solve wrt beta

    beta = lassosolver(n,p,k,mu,lambda,XpX,beta,-X'*y- gamma);

    # perform updates as necessary

    cur_obj = .5*norm(y-X*beta)^2 + mu*norm(beta,1) +lambda*sum(sort(abs(beta))[1:p-k]);

    if abs(cur_obj-prev_obj)/(prev_obj+.01) < REL_TOL # .01 in denominator is for numerical tolerance with zero
      println(I);
      # println(cur_obj);
      # println(prev_obj);
      break; # end AM loops
    end

    prev_obj = cur_obj;

  end

  return copy(beta);


end


### ADMM

function tl_apx_admm(p,k,y,X,mu,lambda,max_iter=2000,rel_tol=1e-6,sigma=1.,print_every=200)

  #####

  # This is known as Algorithm 2 in the paper BCM17 (using augmented Lagranian and alternating direction method of multiplers, a.k.a. ADMM)

  # Inputs:
  #    data matrix `X` and response `y`
  #    `p` is the number of columns of X (i.e., the number of features).
  #    `mu` is the multipler on the usual Lasso penalty: mu*sum_i |beta_i|
  #    `lambda` is the multipler on the trimmed Lasso penalty: lambda*sum_{i>k} |beta_{(i)}|
  #    `solver` is the desired mixed integer optimization solver. This should have SOS-1 capabilities (will return error otherwise).
  #    `bigM` is an upper bound on the largest magnitude entry of beta. if the constraint |beta_i|<= bigM is binding at optimality, an error will be thrown, as this could mean that the value of `bigM` given may have been too small.
  
  # Optional arguments:
  #    `max_iter`---default value of 2000. Maximum number of (outer) ADMM iterations for the algorithm.
  #    `rel_tol`---default value of 1e-6. The algorithm concludes when the relative improvement (current_objective-previous_objective)/(previous_objective + .01) is less than `rel_tol`. The additional `0.01` in the denominator ensures no numerical issues.
  #    `sigma`---default value of 1.0. This is the augmented Lagranian penalty as shown in Algorithm 2 in the paper. 
  #    `print_every`---default value of 200. Controls amount of amount output. Set `print_every=Inf` to suppress output.

  # Output: estimator beta that is a *possible* solution for the problem
  #         minimize_β    0.5*norm(y-X*β)^2 + μ*sum_i |β_i| + λ*T_k(β)

  # Method: alternating minimization approach which finds heuristic solutions to the trimmed Lasso problem. See details in Algorithm 1 in BCM17.

  ##### 

  ADMM_ITER = max_iter;
  REL_TOL = rel_tol;
  # TAU = tau; ---> Could add the scaling parameter tau, but we will neglect to include that in our implementation
  SIGMA = sigma;
  PRINT_EVERY = print_every; # AM will print output on every (PRINT_EVERY)th iteration


  XpX = X'*X; # can separate computation if desired


  # ADMM vars
  beta = zeros(p);#starter;#zeros(p);
  gamma = zeros(p);#starter;#zeros(p);
  q = zeros(p);

  # <solve ADMM>

  prev_norm = 0;
  prev_obj = 0;

  for I=0:ADMM_ITER

    beta = aux_admmwrtbeta(n,p,k,mu,lambda,XpX,beta,q-X'*y- SIGMA*gamma,SIGMA);;

    ### solve wrt gamma

    aux_sb = min(SIGMA/2*(beta.^2) + q.*beta+(1/2/SIGMA)*(q.^2) , (lambda^2)/(2*SIGMA)*ones(p) + lambda*abs(beta+q/SIGMA+lambda/SIGMA*ones(p)),
      (lambda^2)/(2*SIGMA)*ones(p) + lambda*abs(beta+q/SIGMA-lambda/SIGMA*ones(p)));
    sb = sort([(aux_sb[i],i) for i=1:p]);
    zz = zeros(p);
    for i=1:(p-k)
      #println(i);
      zz[sb[i][2]] = 1; 
    end

    for i=1:p
      if zz[i] == 0
        gamma[i] = copy(beta[i]) + copy(q[i])/SIGMA;
      else # zz[i] = 1
        aar = [(SIGMA/2*(beta[i]^2) + q[i]*beta[i]+(1/2/SIGMA)*(q[i]^2) ,    0 ),
             ((lambda^2)/(2*SIGMA) + lambda*abs(beta[i]+q[i]/SIGMA+lambda/SIGMA), beta[i] + q[i]/SIGMA + lambda/SIGMA),
             ((lambda^2)/(2*SIGMA) + lambda*abs(beta[i]+q[i]/SIGMA-lambda/SIGMA), beta[i] + q[i]/SIGMA - lambda/SIGMA)];
        #println(aar);
        gamma[i] = sort(aar)[1][2];
        #println(gamma[i]);
      end
    end


    q = copy(q) + SIGMA*(beta-gamma);

    cur_norm = norm(beta-gamma);
    cur_obj = .5*norm(y-X*beta)^2 + mu*norm(beta,1) +lambda*sum(sort(abs(beta))[1:p-k]);

    #println(abs(cur_norm-prev_norm)/(prev_norm+.01) ," , ", abs(cur_obj-prev_obj)/(prev_obj+.01) );
    if abs(cur_norm-prev_norm)/(prev_norm+.01) + abs(cur_obj-prev_obj)/(prev_obj+.01) < REL_TOL # .01 in denominator is for numerical tolerance with zero
      # println(I);
      break; # end ADMM loops
    end

    prev_norm = cur_norm;
    prev_obj = cur_obj;

  end

  # </ end ADMM>

  return copy(gamma);

end

### convex envelope

function tl_apx_envelope(p,k,y,X,mu,lambda,solver)

  #####

  # Inputs:
  #    data matrix `X` and response `y`
  #    `p` is the number of columns of X (i.e., the number of features).
  #    `mu` is the multipler on the usual Lasso penalty: mu*sum_i |beta_i|
  #    `lambda` is the multipler on the trimmed Lasso penalty: lambda*sum_{i>k} |beta_{(i)}|
  #    `solver` is the desired linear optimization solver.
  
  # Optional arguments: none

  # Output: estimator beta that is a *possible* solution for the problem
  #         minimize_β    0.5*norm(y-X*β)^2 + μ*sum_i |β_i| + λ*T_k(β)
  # beta is found by solving (to optimality) the following linear optimization problem:
  #         minimize_{e,β}    0.5*norm(y-X*β)^2 + μ*sum_i |β_i| + λ*e
  #         subject to        e >= 0;
  #                           e >= sum_i |β_i| - k;
  # As discussed in BCM17, this is the convex relaxation of the first problem when using convex envelopes.

  # Method: alternating minimization approach which finds heuristic solutions to the trimmed Lasso problem. See details in Algorithm 1 in BCM17.

  ##### 

  m = Model(solver = solver);

  @defVar(m, tau >= 0);
  @defVar(m, gamma[1:p] >= 0);
  @defVar(m, beta[1:p] );
  @defVar(m, envelope >= 0);

  @addConstraint(m, gamma[i=1:p] .>= beta[i] );
  @addConstraint(m, gamma[i=1:p] .>= -beta[i] );
  @addConstraint(m, envelope >= sum{lambda*gamma[i], i=1:p} - lambda*k); #convex envelope! 
  #@addConstraint(m, norm2{y[i] - sum{X[i,j]*beta[j], j=1:p} , i=1:n} <= tau);
  @addConstraint(m, dot(beta,.5*X'*X*beta) - dot(y,X*beta)+dot(y,y)/2 <= tau);


  @setObjective(m, Min, tau + sum{mu*gamma[i], i=1:p} + envelope)

  solve(m);

  return getvalue(beta);

end
