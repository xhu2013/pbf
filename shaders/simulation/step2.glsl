// include.glsl is included here
#line 3

layout (local_size_x = 16, local_size_y = 16) in;

struct ParticleInfo
{
	vec3 position;
	vec3 oldposition;
};

layout (std430, binding = 0) readonly buffer ParticleBuffer
{
	ParticleInfo particles[];
};

layout (std430, binding = 3) writeonly buffer LambdaBuffer
{
	float lambdas[];
};

layout (std430, binding = 4) buffer AuxBuffer
{
	vec4 auxdata[];
};

layout (std430, binding = 1) readonly buffer GridCounters
{
	uint gridcounters[];
};

struct GridCell
{
	uint particleids[64];
};

layout (std430, binding = 2) readonly buffer GridCells
{
	GridCell gridcells[];
};

float Wpoly6 (float r)
{
	if (r > h)
		return 0;
	float tmp = h * h - r * r;
	return 1.56668147106 * tmp * tmp * tmp / (h*h*h*h*h*h*h*h*h);
}

float Wspiky (float r)
{
	if (r > h)
		return 0;
	float tmp = h - r;
	return 4.774648292756860 * tmp * tmp * tmp / (h*h*h*h*h*h);
}

vec3 gradWspiky (vec3 r)
{
	float l = length (r);
	if (l > h)
		return vec3 (0, 0, 0);
	float tmp = h - l;
	return (-3 * 4.774648292756860 * tmp * tmp) * r / (l * h*h*h*h*h*h);
}

const ivec3 gridoffsets[27] = {
	ivec3 (-1, -1, -1),
	ivec3 (-1, -1, 0),
	ivec3 (-1, -1, 1),
	ivec3 (-1, 0, -1),
	ivec3 (-1, 0, 0),
	ivec3 (-1, 0, 1),
	ivec3 (-1, 1, -1),
	ivec3 (-1, 1, 0),
	ivec3 (-1, 1, 1),
	ivec3 (0, -1, -1),
	ivec3 (0, -1, 0),
	ivec3 (0, -1, 1),
	ivec3 (0, 0, -1),
	ivec3 (0, 0, 0),
	ivec3 (0, 0, 1),
	ivec3 (0, 1, -1),
	ivec3 (0, 1, 0),
	ivec3 (0, 1, 1),
	ivec3 (1, -1, -1),
	ivec3 (1, -1, 0),
	ivec3 (1, -1, 1),
	ivec3 (1, 0, -1),
	ivec3 (1, 0, 0),
	ivec3 (1, 0, 1),
	ivec3 (1, 1, -1),
	ivec3 (1, 1, 0),
	ivec3 (1, 1, 1)
};

#define FOR_EACH_NEIGHBOUR(var) for (int o = 0; o < 27; o++) {\
		ivec3 ngrid = grid + gridoffsets[o];\
		if (any (lessThan (ngrid, ivec3 (0, 0, 0))) || any (greaterThanEqual (ngrid, GRID_SIZE)))\
			continue;\
		int ngridid = ngrid.y * GRID_WIDTH * GRID_DEPTH + ngrid.z * GRID_WIDTH + ngrid.x;\
		for (uint gridparticle = 0; gridparticle < gridcounters[ngridid]; gridparticle++) {\
			uint var = gridcells[ngridid].particleids[gridparticle];\
			if (var == particleid)\
				continue;
#define END_FOR_EACH_NEIGHBOUR 	}}

void main (void)
{
	uint particleid;
	particleid = gl_GlobalInvocationID.z * gl_NumWorkGroups.y * gl_NumWorkGroups.x
		* gl_WorkGroupSize.x * gl_WorkGroupSize.y
		+ gl_GlobalInvocationID.y * gl_NumWorkGroups.x * gl_WorkGroupSize.x + gl_GlobalInvocationID.x;

	ParticleInfo particle = particles[particleid];

	// compute grid id as hash value
	ivec3 grid;
	grid.x = clamp (int (floor (particle.position.x)), 0, GRID_WIDTH);
	grid.y = clamp (int (floor (particle.position.y)), 0, GRID_HEIGHT);
	grid.z = clamp (int (floor (particle.position.z)), 0, GRID_DEPTH);
	
	int gridid = grid.y * GRID_WIDTH * GRID_DEPTH + grid.z * GRID_WIDTH + grid.x;
	
	float sum_k_grad_Ci = 0;
	float lambda = 0;
	float rho = 0;
	float scorr = 0;

	vec3 grad_pi_Ci = vec3 (0, 0, 0);
	FOR_EACH_NEIGHBOUR(j)
	{
		// highlight neighbours of the highlighted particle
		if (particleid == highlightparticle)
		{
			auxdata[j] = vec4 (0, 1, 0, 1);
		}
	
		// compute rho_i (equation 2)
		float len = length (particle.position - particles[j].position);
		float tmp = Wpoly6 (len);
		rho += tmp;
	
		// compute scorr (equation 13)
		tmp = -tmp / Wpoly6 (tensile_instability_h);
		tmp *= tmp;
		scorr += -tensile_instability_k * tmp * tmp;
			
		// sum gradients of Ci (equation 8 and parts of equation 9)
		// use j as k so that we can stay in the same loop
		uint k = j;
		vec3 grad_pk_Ci = vec3 (0, 0, 0);
		grad_pk_Ci = gradWspiky (particle.position - particles[k].position);
		grad_pk_Ci /= rho_0;
		sum_k_grad_Ci += dot (grad_pk_Ci, grad_pk_Ci);
		
		// now use j as j again and accumulate grad_pi_Ci for the case k=i
		// from equation 8
		grad_pi_Ci += grad_pk_Ci; // = gradWspiky (particle.position - particles[j].position); 
	}
	END_FOR_EACH_NEIGHBOUR
	// add grad_pi_Ci to the sum
	sum_k_grad_Ci += dot (grad_pi_Ci, grad_pi_Ci);
	
	// compute lambda_i (equations 1 and 9)
	float C_i = rho / rho_0 - 1;
	lambda = -C_i / (sum_k_grad_Ci + epsilon);
	
	lambdas[particleid] = lambda + scorr / 2;
}
