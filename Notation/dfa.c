#include <minix/drivers.h>
#include <minix/chardriver.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <minix/ds.h>
#include <minix/ioctl.h>
#include <sys/ioc_dfa.h>

#define BUFFERSIZE 1000

struct State {
    uint8_t next_state[300];
    char is_accepting;
};
static void initState(struct State *state);

static int letters_read;
static uint8_t current_state;
static struct State states[300];
static char buffer[BUFFERSIZE];

static int dfa_open(devminor_t minor, int access, endpoint_t user_endpt);
static int dfa_close(devminor_t close);
static ssize_t dfa_read(devminor_t minor, u64_t position, endpoint_t endpt,
    cp_grant_id_t grant, size_t size, int flags, cdev_id_t id);
static ssize_t dfa_write(devminor_t minor, u64_t position, endpoint_t endpt,
	cp_grant_id_t grant, size_t size, int flags, cdev_id_t id);
static int dfa_ioctl(devminor_t minor, unsigned long request, endpoint_t endpt,
    cp_grant_id_t grant, int flags, endpoint_t user_endpt, cdev_id_t id);

static void sef_local_startup(void);
static int sef_cb_init(int type, sef_init_info_t *info);
static int sef_cb_lu_state_save(int);
static int lu_state_restore(void);

static struct chardriver dfa_tab =
{
    .cdr_open	= dfa_open,
    .cdr_close	= dfa_close,
    .cdr_read	= dfa_read,
    .cdr_write  = dfa_write,
    .cdr_ioctl  = dfa_ioctl
};

static void initState(struct State *state) {
    for (int i = 0; i < 300; i++)
        state->next_state[i] = 0;
    state->is_accepting = 0;
}

static int dfa_open(devminor_t UNUSED(minor), int UNUSED(access), endpoint_t UNUSED(user_endpt)) {
    return OK;
}

static int dfa_close(devminor_t UNUSED(close)) {
    return OK;
}

static ssize_t dfa_read(devminor_t UNUSED(minor), u64_t position,
    endpoint_t endpt, cp_grant_id_t grant, size_t size, int UNUSED(flags),
    cdev_id_t UNUSED(id))
{
    if (position > letters_read)
        return 0;
    if (position + size > letters_read)
        size = (size_t)(letters_read - position);

    for (int s = 0; s < size; s += BUFFERSIZE) {
        int chunk = BUFFERSIZE;
        if (s + chunk >= size)
            chunk = size - s;

        if (states[current_state].is_accepting)
            memset(buffer, 89, chunk);
        else
            memset(buffer, 78, chunk);

        int ret;
        if ((ret = sys_safecopyto(endpt, grant, s, (vir_bytes) buffer, chunk)) != OK)
            return ret;
    }

    return size;
}

static ssize_t dfa_write(devminor_t UNUSED(minor), u64_t UNUSED(position),
    endpoint_t endpt, cp_grant_id_t grant, size_t size, int UNUSED(flags),
    cdev_id_t UNUSED(id))
{
    uint8_t org_state = current_state;

    for (int s = 0; s < size; s += BUFFERSIZE) {
        int ret;
        int chunk = BUFFERSIZE;
        if (s + BUFFERSIZE >= size)
            chunk = size - s;

        if ((ret = sys_safecopyfrom(endpt, grant, s, (vir_bytes) buffer, chunk)) != OK) {
            current_state = org_state;
            return ret;
        }

        for (int i = 0; i < chunk; i++)
            current_state = states[current_state].next_state[buffer[i]];
    }

    letters_read += size;
    return size;
}

static int dfa_ioctl(devminor_t UNUSED(minor), unsigned long request, endpoint_t endpt,
    cp_grant_id_t grant, int UNUSED(flags), endpoint_t user_endpt, cdev_id_t UNUSED(id)) {
        int rc;
        uint8_t buf[3];
        uint8_t p;

        switch (request) {
            case DFAIOCRESET:
                letters_read = 0;
                current_state = 0;
                break;
            case DFAIOCADD:
                rc = sys_safecopyfrom(endpt, grant, 0, (vir_bytes)buf, 3);
                states[buf[0]].next_state[buf[1]] = buf[2];
                letters_read = 0;
                current_state = 0;
                break;
            case DFAIOCACCEPT:
                rc = sys_safecopyfrom(endpt, grant, 0, (vir_bytes)&p, 1);
                states[p].is_accepting = 1;
                break;
            case DFAIOCREJECT:
                rc = sys_safecopyfrom(endpt, grant, 0, (vir_bytes)&p, 1);
                states[p].is_accepting = 0;
                break;
        }

        return OK;
    }

static void sef_local_startup(void) {
    sef_setcb_init_fresh(sef_cb_init);
    sef_setcb_init_lu(sef_cb_init);
    sef_setcb_init_restart(sef_cb_init);

    sef_setcb_lu_prepare(sef_cb_lu_prepare_always_ready);
    sef_setcb_lu_state_isvalid(sef_cb_lu_state_isvalid_standard);
    sef_setcb_lu_state_save(sef_cb_lu_state_save);

    sef_startup();
}

static int sef_cb_init(int type, sef_init_info_t *UNUSED(info)) {
    int do_announce_driver = TRUE;

    switch (type) {
        case SEF_INIT_FRESH:
            letters_read = 0;
            current_state = 0;
            memset(states, 0, sizeof(struct State) * 300);
            for (int i = 0; i < 300; i++)
                initState(&states[i]);
            break;
        case SEF_INIT_LU:
            lu_state_restore();
            do_announce_driver = FALSE;
            break;
    }

    if (do_announce_driver)
        chardriver_announce();

    return OK;
}

static int sef_cb_lu_state_save(int UNUSED(state)) {
    ds_publish_u32("letters_read", letters_read, DSF_OVERWRITE);
    ds_publish_u32("current_state", current_state, DSF_OVERWRITE);
    ds_publish_mem("states", states, sizeof(struct State) * 300, DSF_OVERWRITE);

    return OK;
}

static int lu_state_restore(void) {
    ds_retrieve_u32("letters_read", (uint32_t *)&letters_read);
    ds_delete_u32("letters_read");

    ds_retrieve_u32("current_state", (uint32_t *)&current_state);
    ds_delete_u32("current_state");

    ssize_t size = sizeof(struct State) * 300;
    ds_retrieve_mem("states", (char *)&states, &size);
    ds_delete_mem("states");

    return OK;
}

int main(void) {
    sef_local_startup();

    chardriver_task(&dfa_tab);
    return OK;
}