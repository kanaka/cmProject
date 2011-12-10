######################################################
# cmProject rctag module:
#     Create a branch/tag of a component by finding
#     "trunk" in the URL and transforming it into a 
#     standard, or user overridable branch name.
#     (make rctag^component RCTAG="alpha")
######################################################

ifneq ($(rctag_TARGETS),)
  curDATE=$(shell date +%Y%m%d)
  curTIME=$(shell date +%H%M%S)
  ifeq ($(RCTAG),)
    RCTAG="tag"
  endif
  BRANCH_NAME="{DATE}_{TIME}_rev{REV}_${RCTAG}"
  ifneq ($(filter all,$(rctag_TARGETS)),)
    # Rctag all
    RCTAG_LIST = $(NAMES)
  else
    RCTAG_LIST = $(rctag_TARGETS)
  endif
endif

# FIXME: How can I check that the url transformations, e.g. trunk to rc,
# are actually happening?  Sed commands will just leave the string alone if the
# regexp does not match.  Hard to add good checking logic here.
#
.PHONY: rctag
rctag:
	$(AT)$(foreach X,$(RCTAG_LIST),\
	    $(if $(filter svnco svn,$($(X)_SRC_TYPE)),\
	      rev=$$(svn info $($(X)_GRAFT) | grep "^Revision" | awk '{print $$2}');\
	      src=$$(echo $($(X)_SRC)); \
	      target=$$(echo $$src | sed -e 's#/\(trunk\|branches\)/#/rc/#'); \
	      z="Handle the case of a tag of a tag. Recognize a string that looks"; \
	      z="like an rctag at the end and strip it off."; \
	      target=$$(echo $$target | sed -e 's#/[0-9]\{8\}_[0-9]\{6\}_rev[0-9]*_[^/]*$$##'); \
	      tagname=$$(echo $(BRANCH_NAME) | \
	                sed -e "s/{REV}/$$rev/" \
	                    -e "s/{DATE}/$(curDATE)/" \
	                    -e "s/{TIME}/$(curTIME)/"); \
	      target=$$target/$$tagname;\
	      logmsg="Creating tag $$tagname of revision $$rev of $$src"; \
	      echo $$logmsg; \
	      cmd="svn cp -r $$rev $($(X)_SRC) $$target -m '$$logmsg'"; \
	      if test "$(DRY_RUN)" != 1; then \
		  echo Exec: $$cmd; \
	          eval $$cmd; \
	      else \
		  echo DRY_RUN: svn cp -r $$rev $($(X)_SRC) $$target -m '$$logmsg'; \
	      fi; ))

