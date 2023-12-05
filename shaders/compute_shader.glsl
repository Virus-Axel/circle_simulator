#[compute]
#version 450

layout(local_size_x = 50, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer CircleBuffer {
	float data[];
} circle_data;

layout(set = 0, binding = 1, std430) restrict buffer ZoneIndicies {
	int data[];
} zone_indicies;

layout(set = 0, binding = 2, std430) restrict buffer MiscBuffer {
	float time;
} misc;

layout(set = 1, binding = 0, std430) restrict buffer BoundaryBuffer{
	int shape[];
} boundaries;

layout(set = 1, binding = 1, std430) restrict buffer ConstBuffer{
	float g;
} const_buffer;

void boundary_check(int index){
	int circle_data_index = zone_indicies.data[index];
	if(circle_data.data[circle_data_index * 5 + 1] + circle_data.data[circle_data_index * 5 + 4] > boundaries.shape[1]){
		if(circle_data.data[circle_data_index * 5 + 3] > 0){
			circle_data.data[circle_data_index * 5 + 3] = -circle_data.data[circle_data_index * 5 + 3] * 0.95;
		}
	}
	else if(circle_data.data[circle_data_index * 5 + 1] - circle_data.data[circle_data_index * 5 + 4] < 0.0){
		if(circle_data.data[circle_data_index * 5 + 3] < 0){
			circle_data.data[circle_data_index * 5 + 3] = -circle_data.data[circle_data_index * 5 + 3] * 0.95;
		}
	}
	else if(circle_data.data[circle_data_index * 5] + circle_data.data[circle_data_index * 5 + 4] > boundaries.shape[0]){
		if(circle_data.data[circle_data_index * 5 + 2] > 0){
			circle_data.data[circle_data_index * 5 + 2] = -circle_data.data[circle_data_index * 5 + 2] * 0.95;
		}
	}
	else if(circle_data.data[circle_data_index * 5] - circle_data.data[circle_data_index * 5 + 4] < 0.0){
		if(circle_data.data[circle_data_index * 5 + 2] < 0){
			circle_data.data[circle_data_index * 5 + 2] = -circle_data.data[circle_data_index * 5 + 2] * 0.95;
		}
	}

	circle_data.data[circle_data_index * 5 + 1] += circle_data.data[circle_data_index * 5 + 3] * misc.time;
	circle_data.data[circle_data_index * 5] += circle_data.data[circle_data_index * 5 + 2] * 1.0 * misc.time;
	circle_data.data[circle_data_index * 5 + 3] += const_buffer.g * misc.time;
}

ivec2 get_zone_from_index(int index){
	ivec2 res;
	
	res.x = int(float(gl_WorkGroupSize.x) * circle_data.data[index * 5] / boundaries.shape[0]);
	res.y = int(float(gl_WorkGroupSize.y) * circle_data.data[index * 5 + 1] / boundaries.shape[1]);
	
	return res;
}

ivec2 get_zone_id(){
	ivec2 to_zone;
	to_zone.x = int(gl_GlobalInvocationID.x) / int(gl_WorkGroupSize.x);
	to_zone.y = int(gl_GlobalInvocationID.y);
	
	return to_zone;
}

void add_index_to_zone(ivec2 zone, int new_index){
	int index = int(gl_WorkGroupSize.x * gl_NumWorkGroups.x) * zone.y + zone.x;
	for(int i = 0; i < int(gl_WorkGroupSize.x); i++){
		if(zone_indicies.data[index + i] == -1){
			zone_indicies.data[index + i] = new_index;
			return;
		}
	}
}

float mass(int index){
	return circle_data.data[index * 5 + 4] * circle_data.data[index * 5 + 4] * 3.14;
}
vec2 get_pos(int index){
	return vec2(circle_data.data[index * 5], circle_data.data[index * 5 + 1]);
}
void set_pos(int index, vec2 pos){
	circle_data.data[index * 5] = pos.x;
	circle_data.data[index * 5 + 1] = pos.y;
}
float get_rad(int index){
	return circle_data.data[index * 5 + 4];
}
void set_rad(int index, float rad){
	circle_data.data[index * 5 + 4] = rad;
}
vec2 get_vel(int index){
	return vec2(circle_data.data[index * 5 + 2], circle_data.data[index * 5 + 3]);
}
void set_vel(int index, vec2 vel){
	circle_data.data[index * 5 + 2] = vel.x;
	circle_data.data[index * 5 + 3] = vel.y;
}

void transfer_from_left(){
	ivec2 to_zone = get_zone_id();
	int group_index = int(gl_GlobalInvocationID.x) / int(gl_WorkGroupSize.x);
	if(group_index == 0){
		return;
	}

	for(int i = 0; i < int(gl_WorkGroupSize.x); i++){
		if(zone_indicies.data[i] == -1){
			continue;
		}
		else{
			ivec2 zone = get_zone_from_index(zone_indicies.data[i]);
			if(zone == to_zone){
				add_index_to_zone(zone, zone_indicies.data[i]);
				zone_indicies.data[i] = -1;
			}
		}
	}
}

float distance(int a, int b){
	vec2 p1 = vec2(circle_data.data[b * 5], circle_data.data[b * 5 + 1]);
	vec2 p2 = vec2(circle_data.data[a * 5], circle_data.data[a * 5 + 1]);
	return length(p2 - p1);
}

bool do_circles_collide(int a, int b){
	if(a == -1 || b == -1){
		return false;
	}
	if(circle_data.data[b * 5 + 4] + circle_data.data[a * 5 + 4] > distance(a, b)){
		return true;
	}
	return false;
}

void collide(int a, int b){
	vec2 norm = normalize(get_pos(a) - get_pos(b));
	
	vec2 vel_a = get_vel(a) - (2.0 * mass(b) / (mass(a) + mass(b))) * (get_pos(a) - get_pos(b)) * dot(get_vel(a) - get_vel(b), get_pos(a) - get_pos(b)) / pow(length(get_pos(a) - get_pos(b)), 2);
	vec2 vel_b = get_vel(b) - (2.0 * mass(a) / (mass(b) + mass(a))) * (get_pos(b) - get_pos(a)) * dot(get_vel(b) - get_vel(a), get_pos(b) - get_pos(a)) / pow(length(get_pos(b) - get_pos(a)), 2);
	//vec2 vel_a = get_vel(a) - (2.0 * mass(b) / (mass(a) + mass(b))) * (norm * (get_vel(a) - get_vel(b))) * norm;
	//vec2 vel_b = get_vel(b) - (2.0 * mass(a) / (mass(b) + mass(a))) * (norm * (get_vel(b) - get_vel(a))) * norm;
	
	vel_a.y = vel_a.y;
	vel_b.y = vel_b.y;
	
	set_vel(a, vel_a );
	set_vel(b, vel_b );
	
	set_pos(a, get_pos(a) + norm);
	set_pos(b, get_pos(b) - norm);
}


bool collide_with_zone(ivec2 zone_offset, int circle_index){
	int zone_x = int(gl_GlobalInvocationID.x) / int(gl_WorkGroupSize.x) + zone_offset.x;
	if(zone_x < 0){
		return false;
	}
	if(zone_x >= int(gl_WorkGroupSize.x)){
		return false;
	}
	int zone_y = zone_offset.y + int(gl_GlobalInvocationID.y);
	if(zone_y < 0){
		return false;
	}
	if(zone_y > int(gl_WorkGroupSize.y)){
		return false;
	}
	int index = zone_y * int(gl_WorkGroupSize.x * gl_NumWorkGroups.x) + zone_x * int(gl_WorkGroupSize.x);

	int max_index = index + int(gl_WorkGroupSize.x);
	for(int i = index; i < max_index; i++){
		if(do_circles_collide(zone_indicies.data[i], zone_indicies.data[circle_index])){
			collide(zone_indicies.data[circle_index], zone_indicies.data[i]);
		}
	}
	return false;
}

void collision(){
	int index = int(gl_WorkGroupSize.x * gl_NumWorkGroups.x) * int(gl_GlobalInvocationID.y) + int(gl_GlobalInvocationID.x);
	int max_index = (1 + index / int(gl_WorkGroupSize.x)) * int(gl_WorkGroupSize.x);
	for(int i = index + 1; i < max_index; i++){
		if(do_circles_collide(zone_indicies.data[i], zone_indicies.data[index])){
			collide(zone_indicies.data[index], zone_indicies.data[i]);
		}
	}
	
	collide_with_zone(ivec2(-1, 0), index);
	collide_with_zone(ivec2(-1, -1), index);
	collide_with_zone(ivec2(0, -1), index);
	collide_with_zone(ivec2(1, -1), index);
	collide_with_zone(ivec2(1, 0), index);
	collide_with_zone(ivec2(1, 1), index);
	collide_with_zone(ivec2(0, 1), index);
}

void main() {
	ivec3 workgroupSize = ivec3(gl_WorkGroupSize);
	ivec3 numWorkGroups = ivec3(gl_NumWorkGroups);
	ivec3 globalSize = workgroupSize * numWorkGroups;
	
	int index = globalSize.x * int(gl_GlobalInvocationID.y) + int(gl_GlobalInvocationID.x);
	
	if(zone_indicies.data[index] == -1){
		return;
	}

	boundary_check(index);
	collision();
}
