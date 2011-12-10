######################################################
# cmProject overlay module:
#     Overlay a scx1000 checkout so that full vtest
#     can be run against a cmProject.
######################################################

# This code is hairy but essentially it's just doing a table lookup to
# see if there are any conflicts that prevent overlaying and also to
# determine how to set up the overlay links.
#
#                                       SOURCES
#
#                   |     A.    |     B.    |     C.    |     D.    |
#                   |  input in |  input == | ovrlay in |  input != |
#                   |   ovrlay  |   ovrlay  |  input    |   ovrlay  |
#     --------------|-----------|-----------|-----------|-----------|
#      1. input in  |   error   |   error   |   error   |   error   |
#          ovrlay   |           |           |           |           |
#  G  --------------|-----------|-----------|-----------|-----------|
#  R   2. input ==  |   error   |   no-op   |   error   |   error   |
#  A       ovrlay   |           |           |           |           |
#  F  --------------|-----------|-----------|-----------|-----------|
#  T   3. ovrlay in |   error   |   error   |   no-op   |   error   |
#  S       input    |           |           |           |           |
#     --------------|-----------|-----------|-----------|-----------|
#      4. input !=  |   error   |   local   |   error?  |  ovrlay   |
#          ovrlay   |           |  symlink  |           |  symlink  |
#     --------------|-----------|-----------|-----------|-----------|

ifneq ($(filter %overlay,$(MAKECMDGOALS)),)
  # We are doing overlay/unoverlay
  SCX := $(MAIN_REPO)/scx1000/trunk
  # Generate graft and source lists with trailing /'s trimmed
  INPUT_GRAFTS = $(patsubst %/,%,$(foreach X,$(NAMES), \
    $(if $(filter $(SCX)%,$($(X)_ORIG)),$($(X)_GRAFT),) ))
  INPUT_SOURCES = $(patsubst %/,%,$(foreach X,$(NAMES), \
    $(if $(filter $(SCX)%,$($(X)_ORIG)),$($(X)_ORIG),) ))
  # Chop off the repo base to get the un-relocated relative path
  ALL_SSDIRS = $(patsubst $(SCX)/%,%,$(filter $(SCX)%,$(INPUT_SOURCES))) sw hw
  # Chop off last dir, then include every leading path, and sort
  # subdirs to be before their parent dirs
  OVERLAY_DIRS = $(shell \
      for DIR in `echo $(ALL_SSDIRS) | sed 's|/[^/ ]* | |g'`; do \
        TEMP=""; \
        for JOT in `echo $$DIR | sed 's:/: :g'`; do \
          TEMP="$$TEMP$$JOT/"; \
          echo $$TEMP | sed 's:/$$::'; \
        done; \
      done | sort -r | uniq)

  ifneq ($(filter overlay,$(MAKECMDGOALS)),)
    ifdef OVERLAY_SCX1000
      ifeq ($(wildcard $(OVERLAY_SCX1000)/Project_Root),)
        $(error Invalid overlay directory: $(OVERLAY_SCX1000))
      endif
      SNAME = overlay_$$(patsubst /,_,$(1))
      # Generate a properly pruned list of directories to symlink
      OVERLAY_GRAFTS = diags impl specs $(shell cd $(OVERLAY_SCX1000); \
            EXCL='-e .*\.svn'; \
            for XX in $(OVERLAY_DIRS); do \
              find $$XX -maxdepth 1 -mindepth 1 | grep -v $$EXCL; \
              EXCL="$${EXCL} -e ^$$XX"; \
            done)
    else
      $(error You must set OVERLAY_SCX1000 variable in order to overlay)
    endif
  endif
endif
ifneq ($(wildcard .proj_overlays),)
  # These operations are prohibited while overlayed
  ifneq ($(strip $(filter pop%,$(MAKECMDGOALS))$(filter tag%,$(MAKECMDGOALS))),)
    $(error Overlay mode prevents "make $(strip $(filter pop%,$(MAKECMDGOALS)) \
             $(filter tag%,$(MAKECMDGOALS)))", run "make unoverlay" first)
  endif
endif

define checkINPUT_WITHIN_INPUT
# One input within another input
ifneq ($$(filter $(1)/%,$$(INPUT_SOURCES)),)
  $$(error Input source(s) '$$(filter $(1)/%,$$(INPUT_SOURCES))' \
           within input source '$(1)'. Not legal in overlay mode)
endif
# Repeated input
ifneq ($$(words $$(filter $(1)%,$$(INPUT_SOURCES))),1)
  $$(error Input source(s) '$(1)' used in two places. \
           Not legal in overlay mode)
endif
endef
$(foreach X,$(INPUT_SOURCES),$(eval $(call checkINPUT_WITHIN_INPUT,$(X))))

define checkINPUT_WITHIN_OVERLAY
ifneq ($$(filter $$(SCX)/$(1)/%,$$(INPUT_SOURCES)),)
  # Col A - Input source within overlay source
  $$(error Input source(s) '$$(filter $$(SCX)/$(1)/%,$$(INPUT_SOURCES))' \
           within overlay source '$$(SCX)/$(1)')
endif
ifneq ($$(filter $(1)/%,$$(INPUT_GRAFTS)),)
  # Row 1 - Input graft within overlay graft
  $$(error Input graft(s) '$$(filter $(1)/%,$$(INPUT_GRAFTS))' \
           within overlay graft '$(1)')
endif
endef
$(foreach X,$(OVERLAY_GRAFTS),$(eval $(call checkINPUT_WITHIN_OVERLAY,$(X))))

define checkCOMMON_PARENT
ifeq ($(1),$$(patsubst %/,%,$$($(2)_GRAFT)))
  # Row 2 - Grafts are identical
  ifeq ($$(SCX)/$(1),$$(patsubst %/,%,$$($(2)_ORIG)))
    # Row 2, Col B - Sources are identical, force no-op
    $(SNAME)_SRC :=
  else
    # Row 2, Col C,D - Sources are not identical
    $$(error Same graft point '$(1)' but overlay source '$$(SCX)/$(1)' \
             is different than input source '$$(patsubst %/,%,$$($(2)_ORIG))')
  endif
else
  # Row 3,4 - Grafts are not identical
  ifneq ($$(filter $$(patsubst %/,%,$$($(2)_GRAFT))/%,$(1)),)
    # Row 3 - Overlay graft within input graft
    ifneq ($$(filter $$(patsubst %/,%,$$($(2)_ORIG))/%,$$(SCX)/$(1)),)
      # Row 3, Col C - Overlay source within input source, force no-op
      $(SNAME)_SRC :=
    else
      # Row 3, Col B,D - Overlay source not within input source
      $$(error Overlay graft '$(1)' within input graft '$$($(2)_GRAFT)', \
               but overlay source '$$(SCX)/$(1)' not \
               within input source '$$($(2)_ORIG)')
    endif
  else
    # Row 4 - Grafts are not identical nor within each other
    ifneq ($$(filter $$(patsubst %/,%,$$($(2)_ORIG))/%,$$(SCX)/$(1)),)
      # Row 4, Col C - Overlay source within input source
      $$(error Overlay graft '$(1)' and input graft '$$($(2)_GRAFT)' are \
               different, but overlay source '$$(SCX)/$(1)' is \
               within input source '$$(patsubst %/,%,$$($(2)_ORIG))')
    endif
  endif
endif
endef
$(foreach X,$(OVERLAY_GRAFTS),\
  $(foreach NAME,$(NAMES),$(eval $(call checkCOMMON_PARENT,$(X),$(NAME)))))


define doOVERLAY
ifeq ($$(origin $(SNAME)_SRC),undefined)
  ifneq ($$(filter $$(SCX)/$(1),$$(INPUT_SOURCES)),)
    # Row 4, Col B - Input and overlay sources are the same: local symlink
    $(SNAME)_SRC := $$(shell readlink -f \
      $$(foreach X,$$(NAMES),\
        $$(if $$(filter $$(SCX)/$(1),$$(patsubst %/,%,$$($$(X)_ORIG))),\
          $$($$(X)_GRAFT),)))
    $(SNAME)_GRAFT := $(1)
    OVERLAY_INPUTS += $(SNAME)
  else
    # Row 4, Col D - Input and overlay sources are different: overlay symlink
    $(SNAME)_SRC := $$(OVERLAY_SCX1000)/$(1)
    $(SNAME)_GRAFT := $(1)
    OVERLAY_INPUTS += $(SNAME)
  endif
endif
endef
$(foreach X,$(OVERLAY_GRAFTS),$(eval $(call doOVERLAY,$(X))))

# Overlay populates .proj_overlays with the list of symlinks.
# Unoverlay uses that to clean up because OVERLAY_GRAFTS may have
# changed or been removed in the mean time.
.PHONY: overlay unoverlay
unoverlay:
	$(AT)for X in $$(head -n 1 .proj_overlays 2>/dev/null); do \
	  [ -h $$X ] && rm $$X; \
	done; \
	$(foreach X,$(OVERLAY_DIRS),rmdir 2>/dev/null $(X);) \
	[ -e .proj_overlays ] && rm .proj_overlays || true
overlay: unoverlay
	$(AT)$(foreach X,$(OVERLAY_DIRS),mkdir -p $(X);) \
	$(foreach X,$(OVERLAY_INPUTS),[ -e $($(X)_GRAFT) ] || \
                                        ln -s $($(X)_SRC) $($(X)_GRAFT);) \
	echo $(foreach X,$(OVERLAY_INPUTS),$($(X)_GRAFT)) > .proj_overlays
