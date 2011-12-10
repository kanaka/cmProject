######################################################
# cmProject: Project/configuration management Makefile
#
# Copyright (c) 2008 SiCortex, Inc
# Created by Joel Martin: <joel.martin@sicortex.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program*; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# See the file LICENSE that came with this source file for the full
# terms and conditions of the GNU General Public License.
######################################################

######################################################
# Site specific settings
######################################################

MAIN_REPO := svn+ssh://svn.sicortex.com/svn/master

# Project_Root still needs a stub _SRC in Project.def so
# that it can be pegged to a specific revision.
Project_Root_SRC = $(MAIN_REPO)/scx1000/trunk/Project_Root

# Objects in the "stash" must always be reproducible
STASH := /stash

######################################################
# Project definition defaults
######################################################

# Define srcdir/buildir early so they can be in Project.def
srcdir = $(shell readlink -f .)
builddir ?= $(shell readlink -f .)/build

# This the top level default rule (must be before Project.def)
all default: default_real

# Do not build Project_Root
Project_Root_BUILD_TYPE = none
Project_Root_MKDIR:

# Pull in the project definition, but allow the user to override
Project_Def_File = Project.def   # For backward compatibility
DEF_FILE = $(Project_Def_File)
include $(DEF_FILE)

# Don't permit Project.def includes for now since it complicates pegging
ifneq ($(words $(filter-out $(DEF_FILE),$(MAKEFILE_LIST))),1)
  $(error Use of includes in Project.def is not supported)
endif

######################################################
# Set attribute defaults and group them by type
######################################################

# CMDEBUG: Print out cmProject shell commands
ifeq ($(CMDEBUG),)
  AT = @
endif

# Based on *_SRC variables, create the list of NAMES
NAMES = $(patsubst %_SRC,%,$(filter %_SRC,$(.VARIABLES)))

# Set defaults for variables not set explicitly in Project.def.
# Generate some lists of stuff based on Project.def variables.
define setDEFAULTS
  $(1)_ORIG      ?= $$($(1)_SRC)
  ifeq ($$($(1)_REV),)                      # Force blank _REV to 'HEAD'
    $(1)_REV = HEAD
  endif
  $(1)_MVARS     ?=

  # SRC_TYPE defaults depend on SRC
  ifneq ($$(findstring ://,$$($(1)_SRC)),)  # SRC contains '://'
    $(1)_SRC_TYPE  ?= svn
  else
    ifneq ($$(filter /%,$$($(1)_SRC)),)     # SRC begins with '/'
      $(1)_SRC_TYPE  ?= link
    else
      ifeq ($$(strip $$($(1)_SRC)),)        # SRC is blank
        $(1)_SRC_TYPE  ?= local
      else                                  # SRC is relative path
        $(1)_SRC_TYPE  ?= local
        $(1)_GRAFT     ?= $$($(1)_SRC)
      endif
    endif
  endif

  # Validate SRC_TYPE
  ifneq ($$(filter-out svnco svn hg link local, $$($(1)_SRC_TYPE)),)
    $$(error Illegal value '$$($(1)_SRC_TYPE)' for $(1)_SRC_TYPE)
  endif

  $(1)_GRAFT     ?= $(1)
  $(1)_BUILDDIR  ?= $(1)
  ifneq ($$(filter /%,$$($(1)_BUILDDIR)),)     # begins with '/'
    $(1)_BLDDIR    ?= $$($(1)_BUILDDIR)
  else
    $(1)_BLDDIR    ?= $$(builddir)/$$($(1)_BUILDDIR)
  endif

  # BUILD_TYPE defaults depend on SRC_TYPE
  ifneq ($$(filter svnco svn,$$($(1)_SRC_TYPE)),) # SRC_TYPE is 'svn'
    $(1)_BUILD_TYPE ?= source
    SVN_INPUTS += $(1)
    ifeq ($$($(1)_REV),HEAD)
      SVN_INPUTS_UNPEGGED += peg_$(1)
    endif
    ifneq ($$(strip $$(filter -%,$$($(1)_REV))$$(filter r%,$$($(1)_REV))),)
     $$(error Illegal format '$$($(1)_REV)' for $(1)_REV)
    endif
  endif
  ifeq ($$($(1)_SRC_TYPE),hg)            # SRC_TYPE is 'hg'
    $(1)_BUILD_TYPE ?= source
    HG_INPUTS += $(1)
    ifeq ($$($(1)_REV),HEAD)
      HG_INPUTS_UNPEGGED += peg_$(1)
    endif
    ifneq ($$(strip $$(filter -%,$$($(1)_REV))$$(filter r%,$$($(1)_REV))),)
     $$(error Illegal format '$$($(1)_REV)' for $(1)_REV)
    endif
  endif
  ifeq ($$($(1)_SRC_TYPE),link)             # SRC_TYPE is 'link'
    $(1)_BUILD_TYPE ?= tgz
    LINK_INPUTS += $(1:%/=%)
    ifneq ($$(filter-out $$(STASH)/%,$$($(1)_SRC)),)
      ifneq ($$(filter /%,$$($(1)_SRC))$$(findstring ..,$$($(1)_SRC)),)
        LINK_INPUTS_UNPEGGED += peg_$(1:%/=%)
      endif
    endif
  endif
  ifeq ($$($(1)_SRC_TYPE),local)            # SRC_TYPE is 'local'
    $(1)_BUILD_TYPE ?= source
  endif

  # Validate BUILD_TYPE
  ifneq ($$(filter-out source kernelmod kernel tgz link none, $$($(1)_BUILD_TYPE)),)
    $$(error Illegal value '$$($(1)_BUILD_TYPE)' for $(1)_BUILD_TYPE)
  endif

  # Sort into correct build bucket lists
  ifeq ($$($(1)_BUILD_TYPE),source)
    BUILD_SOURCE += $(1)
  endif
  ifeq ($$($(1)_BUILD_TYPE),kernelmod)
    BUILD_KERNELMOD += $(1)
    ifeq ($$($(1)_DEPS),)
      $$(error $(1)_DEPS must be set to kernel to build against)
    endif
  endif
  ifeq ($$($(1)_BUILD_TYPE),kernel)
    $(1)_DEFCONFIG ?= sc1000_smp_defconfig
    BUILD_KERNEL += $(1)
  endif
  ifeq ($$($(1)_BUILD_TYPE),tgz)
    BUILD_TGZ += $(1)
  endif
  ifeq ($$($(1)_BUILD_TYPE),link)
    ifeq ($$($(1)_SRC_TYPE),link)
      BUILD_REMOTELINK += $(1)
    else
      BUILD_LINK += $(1)
    endif
  endif
  ifeq ($$($(1)_BUILD_TYPE),none)
    BUILD_NONE += $(1)
  endif
endef

$(foreach NAME,$(NAMES),$(eval $(call setDEFAULTS,$(NAME))))

######################################################
# Compound / Subtarget rules
#   Syntax: make target^subtarget^subtarget...
######################################################

# Build targets should not automatically have 'all' so we use the
# token '__all__' and remove it from the build targets.
define setSUBTGTS
$(1): $(2)
$(2)_TARGETS += $$(wordlist 2,100,$$(subst __all__,all,$$(subst ^, ,$(1))))
$(2)_BLDTARGETS += $$(wordlist 2,100,$$(subst __all__,,$$(subst ^, ,$(1))))
endef
$(foreach Y,$(foreach X,$(MAKECMDGOALS), \
  $(if $(findstring ^,$(X)),$(X),$(X)^__all__)), \
    $(eval $(call setSUBTGTS,$(Y),$(word 1,$(subst ^, ,$(Y))))))

######################################################
# Input generation rules ('make populate')
#   1) Recreate symlinks for 'link' inputs
#   2) Set the svn externals for 'svn' inputs
#   3) `svn update` on the sub-targets or the top level
######################################################

define POP_SVN
  $(if $($(1)_GRAFT), \
    $(if $(wildcard $($(1)_GRAFT)), \
      svn up -r$($(1)_REV) $($(1)_GRAFT); \
      , \
      svn co -r$($(1)_REV) $($(1)_SRC) $($(1)_GRAFT);) \
    , \
    $(error populate sub-target $(1) [$($(1)_GRAFT)] not found) )
endef

define POP_HG
  $(if $($(1)_GRAFT), \
    $(if $(wildcard $($(1)_GRAFT)), \
      hg pull -q -R $($(1)_GRAFT); \
      , \
      hg clone -q $($(1)_SRC) $($(1)_GRAFT); ) \
    hg update -q -R $($(1)_GRAFT) $($(1)_REV:HEAD=tip); \
    echo -e "hg graft '$($(1)_GRAFT)' at revision '$$(hg -R $($(1)_GRAFT) id)'"; \
    , \
    $(error populate sub-target $(1) [$($(1)_GRAFT)] not found) )
endef

define POP_LINK
  $(if $($(1)_GRAFT), \
    rm -f $($(1)_GRAFT:%/=%); \
    mkdir -p `dirname  $($(1)_GRAFT)`; \
    ln -sf $($(1)_SRC) $($(1)_GRAFT:%/=%); \
    , \
    $(error populate sub-target $(1) [$($(1)_GRAFT)] not found) )
endef

POP_LIST = $(subst all,$(SVN_INPUTS) $(HG_INPUTS) $(LINK_INPUTS), \
             $(pop_TARGETS) $(populate_TARGETS))

.PHONY: pop populate
pop populate:
	$(AT) \
	svn propset svn:externals "`echo -e "$(foreach X,$(SVN_INPUTS),$($(X)_GRAFT)	$(if $(filter HEAD,$($(X)_REV)),,-r$($(X)_REV)) $($(X)_SRC)\n)" | sort`" .; \
	$(if $(filter all,$(pop_TARGETS) $(populate_TARGETS)), svn up; ) \
	$(foreach X,$(POP_LIST), \
	  $(if $(filter all,$(pop_TARGETS) $(populate_TARGETS)), \
	    , \
	    $(if $(filter svnco svn,$($(X)_SRC_TYPE)),$(call POP_SVN,$(X))) ) \
	  $(if $(filter hg,$($(X)_SRC_TYPE)), $(call POP_HG,$(X))) \
	  $(if $(filter link,$($(X)_SRC_TYPE)), $(call POP_LINK,$(X))) )


######################################################
# Output build rules ('make')
######################################################

# builddir must exist for output rules
$(shell [ -e $(builddir) ] || mkdir $(builddir))

define RULE_ALL
.PHONY: $(1)_MKDIR $(1)_PRE $(1)_BUILD $(1)_POST $$($(1)_BLDDIR) \
        $$($(1)_BLDDIR)/ $(1)
$(1)_PRE: $(1)_MKDIR $$($(1)_DEPS)
$(1)_BUILD: $(1)_PRE
$(1)_POST: $(1)_BUILD
$$($(1)_BLDDIR): $(1)_POST
$$($(1)_BLDDIR)/: $(1)_POST
$(1): $$($(1)_BLDDIR)
endef
$(foreach OUTPUT,$(BUILD_TGZ) $(BUILD_SOURCE) $(BUILD_KERNEL) \
          $(BUILD_KERNELMOD) $(BUILD_LINK) $(BUILD_REMOTELINK) \
          $(BUILD_NONE),$(eval $(call RULE_ALL,$(OUTPUT))))

define RULE_TGZ
$(1)_MKDIR:
	$(AT)mkdir -p $$($(1)_BLDDIR).dir
$(1)_BUILD:
	$(AT)echo -e "tgz: unpacking to $$($(1)_BLDDIR)"; \
	link=$$($(1)_SRC); \
	if [ $$($(1)_BLDDIR) -ot $$$$link ]; then \
	  list=`tar xvzf $$$$link -C $$($(1)_BLDDIR).dir`; \
	  first=`echo "$$$$list" | head -n 1`; \
	  if [ `echo "$$$$list" | wc -l` -eq 1 ]; then \
	    ln -sf $$($(1)_BLDDIR).dir/$$$$first $$($(1)_BLDDIR); \
	  else \
	    ln -sf $$($(1)_BLDDIR).dir $$($(1)_BLDDIR); \
	  fi; \
	  touch $$($(1)_BLDDIR); \
	else \
	  echo -e "tgz: already unpacked and up to date"; \
	fi; \
	echo -e "tgz: finished $$($(1)_BLDDIR)"
endef
$(foreach OUTPUT,$(BUILD_TGZ),$(eval $(call RULE_TGZ,$(OUTPUT))))

define RULE_SOURCE
$(1)_MKDIR:
	$(AT)mkdir -p $$($(1)_BLDDIR)
$(1)_BUILD:
	$(AT)mysrcdir=`readlink -f $$($(1)_GRAFT)/`; \
	mybuilddir=`readlink -f $$($(1)_BLDDIR)`; \
	cd $$$$mybuilddir; \
	if [ -e "$$$$mysrcdir/configure" ]; then \
	  if [ ! -f "$$$$mybuilddir/Makefile" ] || \
	     [ "$$$$mybuilddir/Makefile" -ot "$$$$mysrcdir/configure" ]; then \
	    echo $$($(1)_EVARS) $$$$mysrcdir/configure $$($(1)_CARGS); \
	    $$($(1)_EVARS) $$$$mysrcdir/configure $$($(1)_CARGS); \
	  fi; \
	  $$($(1)_EVARS) $$(MAKE) -f $$$$mybuilddir/Makefile \
	    $$($(1)_MVARS) $$($(1)_BLDTARGETS); \
	else \
	  mymakefile=`find $$$$mysrcdir/Makefile $$$$mybuilddir/Makefile 2>/dev/null | tail -n 1`; \
	  [ -n "$$$$mymakefile" ] || exit 0; \
	  $$($(1)_EVARS) $$(MAKE) -f $$$$mymakefile \
	    builddir=$$$$mybuilddir srcdir=$$$$mysrcdir PROJECT=$$(srcdir) \
	    OBJ_DEPS="$$($(1)_DEPS)" PROJECT_builddir=$$(builddir) \
	    SRC_DEPS="$$(foreach X,$$($(1)_DEPS),$$($$(X)_GRAFT))" \
	    $$($(1)_MVARS) $$($(1)_BLDTARGETS); \
	fi
endef
$(foreach OUTPUT,$(BUILD_SOURCE),$(eval $(call RULE_SOURCE,$(OUTPUT))))

define RULE_KERNEL
$(1)_MKDIR:
	$(AT)mkdir -p $$($(1)_BLDDIR)
$(1)_BUILD:
	$(AT)mysrcdir=`readlink -f $$($(1)_GRAFT)/`; \
	mybuilddir=`readlink -f $$($(1)_BLDDIR)`; \
	cd $$$$mysrcdir; \
	[ -e $$$$mybuilddir/.config ] || \
	$$($(1)_EVARS) $$(MAKE) O=$$$$mybuilddir ARCH=mips CROSS_COMPILE=sc \
	  $$(subst _defconfig,,$$($(1)_DEFCONFIG))_defconfig; \
	$$($(1)_EVARS) $$(MAKE) O=$$$$mybuilddir ARCH=mips CROSS_COMPILE=sc \
	  $$($(1)_MVARS) $$($(1)_BLDTARGETS)
endef
$(foreach OUTPUT,$(BUILD_KERNEL),$(eval $(call RULE_KERNEL,$(OUTPUT))))

define RULE_KERNELMOD
$(1)_MKDIR:
	$(AT)mkdir -p $$($(1)_BLDDIR)
$(1)_BUILD:
	$(AT)mysrcdir=`readlink -f $$($(1)_GRAFT)/`; \
	mybuilddir=`readlink -f $$($(1)_BLDDIR)`; \
	mykbuilddir=`readlink -f $$($$(word 1,$$($(1)_DEPS))_BLDDIR)`; \
	cd $$$$mysrcdir && \
	tar --exclude *.svn* -cf - *| tar -xf - -C $$$$mybuilddir && \
	$$($(1)_EVARS) $$(MAKE) -C $$$$mykbuilddir M=$$$$mybuilddir ARCH=mips CROSS_COMPILE=sc \
	  $$($(1)_MVARS) $$($(1)_BLDTARGETS)
endef
$(foreach OUTPUT,$(BUILD_KERNELMOD),$(eval $(call RULE_KERNELMOD,$(OUTPUT))))

define RULE_LINK
$(1)_MKDIR:
$(1)_BUILD:
	$(AT)echo -e "link: creating $$($(1)_BLDDIR)"; \
	rm -f $$($(1)_BLDDIR); \
	mysrcdir=`readlink -f $$($(1)_GRAFT)/`; \
	ln -sf $$$$mysrcdir $$($(1)_BLDDIR); \
	echo -e "link: finished $$($(1)_BLDDIR)"
endef
$(foreach OUTPUT,$(BUILD_LINK),$(eval $(call RULE_LINK,$(OUTPUT))))

define RULE_REMOTELINK
$(1)_MKDIR:
$(1)_BUILD:
	$(AT)echo -e "remote link: creating $$($(1)_BLDDIR)"; \
	rm -f $$($(1)_BLDDIR); \
	ln -sf $$($(1)_SRC) $$($(1)_BLDDIR)
	echo -e "remote link: finished $$($(1)_BLDDIR)"
endef
$(foreach OUTPUT,$(BUILD_REMOTELINK),$(eval $(call RULE_REMOTELINK,$(OUTPUT))))

# Build the outputs
.PHONY: default_real
default_real: $(foreach NAME,$(NAMES),$($(NAME)_BLDDIR))

######################################################
# Clean rules ('make clean')
######################################################

all_BLDDIR = $(builddir)/

# Do not allow invalid clean sub-targets
$(foreach X,$(clean_TARGETS), \
  $(if $($(X)_BLDDIR),,$(error clean sub-target '$(X)' not found)))

.PHONY: clean
clean:
	$(AT)$(foreach X,$(clean_TARGETS),cdir=$($(X)_BLDDIR); \
	    [ -n "$${cdir//\//}" ] && \
	      echo "Cleaning $${cdir}" && rm -rf $${cdir}{,.dir}; true;)

######################################################
# Peg rules ('make peg' 'make unpeg')
######################################################

# Peg/unpeg sub-targets
ifeq ($(filter all,$(peg_TARGETS) $(unpeg_TARGETS)),)
  # Build peg list and make sure each item exists and is unpegged
  PEG_LIST = $(addprefix peg_,$(strip $(foreach X,$(peg_TARGETS), \
               $(if $(filter peg_$(X),$(SVN_INPUTS_UNPEGGED) $(HG_INPUTS_UNPEGGED)),$(X), \
                 $(error failed to peg '$(X)': undefined or already pegged)))))
  # Build unpeg list and make sure each item exists and is pegged
  UNPEG_LIST = $(strip $(foreach X,$(unpeg_TARGETS), \
                 $(if $(filter-out HEAD,$($(X)_REV)),$(X), \
                   $(error failed to unpeg '$(X)': undefined or unpegged))))
  PEG_TAG =
endif

# Peg all
ifneq ($(filter all,$(peg_TARGETS)),)
  # peg all will add a comment tag
  PEG_LIST = $(SVN_INPUTS_UNPEGGED) $(HG_INPUTS_UNPEGGED)
  PEG_TAG = \# Added by 'make peg'
endif

# Unpeg all
ifneq ($(filter all,$(unpeg_TARGETS)),)
  # unpeg of all will remove the revisions added by peg all.
  UNPEG_LIST = $(SVN_INPUTS) $(HG_INPUTS)
  PEG_TAG = \# Added by 'make peg'
endif


# Peg svn and hg grafts to the current checked-out revision.
.PHONY: $(SVN_INPUTS_UNPEGGED) $(HG_INPUTS_UNPEGGED)
$(SVN_INPUTS_UNPEGGED) $(HG_INPUTS_UNPEGGED): peg_% :
	$(AT) \
	if [ "$($*_SRC_TYPE)" = "hg" ]; then \
	  rev=$$(hg -R $($*_GRAFT) tip --template "{node}"); \
	else \
	  rev=$$(svn st -v $($*_GRAFT) | awk '{print $$2}' | sort -n | tail -n1); \
	fi; \
	if [ -n "$$rev" ]; then \
	  echo Pegging $* to "$$rev"; \
	  sed -i "s:^\($*_REV.*\)$$:#\1:" $(DEF_FILE); \
	  sed -i "s:^\($*_SRC[^_A-z].*\)$$:\1\n$*_REV = $$rev $(PEG_TAG):" $(DEF_FILE); \
	else \
	  echo Could not get version for \'$*\'. Perhaps run \'make pop\'; \
	  exit 1; \
	fi

.PHONY: peg unpeg
peg: $(PEG_LIST)
	$(if $(PEG_LIST),$(AT)svn st $(DEF_FILE),)

unpeg:
	$(AT)$(foreach X,$(UNPEG_LIST), \
	      grep -q "^$(X)_REV.*$(PEG_TAG)" $(DEF_FILE) && \
	        echo Unpegging $(X) && \
	        sed -i "\:^$(X)_REV.*$(PEG_TAG):d" $(DEF_FILE) || true; )

######################################################
# Tag rules ('make tag')
######################################################

ifneq ($(filter tag%,$(MAKECMDGOALS)),)
  # Make sure svn inputs are pegged and links are to binary repo
  ifneq ($(strip $(SVN_INPUTS_UNPEGGED)),)
    $(error Unpegged 'svn' inputs: [ $(SVN_INPUTS_UNPEGGED:peg_%=%) ]. \
             Run "make peg" to peg first)
  endif
  ifneq ($(strip $(HG_INPUTS_UNPEGGED)),)
    $(error Unpegged 'hg' inputs: [ $(HG_INPUTS_UNPEGGED:peg_%=%) ]. \
             Run "make peg" to peg first)
  endif
  ifneq ($(strip $(LINK_INPUTS_UNPEGGED)),)
    $(error 'link' inputs outside '$(STASH)' prevent tagging. \
      Violations: [ $(LINK_INPUTS_UNPEGGED:peg_%=%) ])
  endif
  ifeq ($$(findstring ://,$(TAG)),)  # SRC missing '://'
    $(error TAG does not appear to be a subversion URL)
  endif
endif
ifeq ($(filter tag,$(MAKECMDGOALS)),tag)
  ifeq ($(TAG),)
    $(error You must set TAG in order to tag)
  endif
endif

# TODO: official svn config used for tagging (with ignores set to sane
# defaults)

# For svn grafts, use "svn st -v" and trim the output of valid
# elements to give the list of things that violate tagging.
# For hg grafts it's easier. "hg st" shows everything that would
# violate tagging.
.PHONY: tag_check
tag_check:
	@echo Sanity checking before tagging
	$(AT)local_rev=$$(svn info . |grep "^Revision" |awk '{print $$2}'); \
	svnst=$$(svn st -v .); \
	local=$$(echo "$$svnst" | sed -n "H; /^Performing/ Q; p"); \
	exts=$$(echo "$$svnst" | sed -n "/^Performing/,$$ p"); \
	violations=$$((echo "$$local" | grep "^(\?|!)"; echo "$$exts"; ) \
	  | egrep -v -e "^$$" \
	  $(foreach X,$(SVN_INPUTS),-e "^      *$($(X)_REV)") \
	  $(foreach X,$(SVN_INPUTS),-e "^Performing .* '$($(X)_GRAFT)'$$") \
	  $(foreach X,$(SVN_INPUTS),-e "^\?     *$($(X)_GRAFT)$$") \
	  $(foreach X,$(HG_INPUTS),-e "^\?     *$($(X)_GRAFT)$$") \
	  $(foreach X,$(LINK_INPUTS),-e "^\?     *$($(X)_GRAFT)$$"); \
	  \
	  $(foreach X,$(HG_INPUTS),\
	    hg parents -R $($(X)_GRAFT) --template "$($(X)_GRAFT) {node}" \
	      | egrep -v "$($(X)_REV: =)"; \
	    hg st -R $($(X)_GRAFT) \
	      | sed "s:  *:$$(printf '%39s')$($(X)_GRAFT)/:"; ) \
	  \
	  for link in $$(find run -type l); do \
	    readlink -f "$$link" \
	        | grep -sv "^$$(readlink -f $(srcdir))" \
	        | grep -qsv "^$$(readlink -f $(STASH))" \
	        && echo "$$link -> $$(readlink -f $$link) *** Not in project or binary repo ***"; \
	  done; \
	); \
	if [ $$(echo $$violations | wc -w) -ne 0 ]; then \
	  echo "The following prevent tagging: "; \
	  echo "$$violations"; \
	  exit 1; \
	fi

# Sanity check and then tag this project by copying from working copy
# to the tag location. 
.PHONY: tag
tag: tag_check
	$(AT)\
	if svn ls $(TAG) >/dev/null 2>&1; then \
	  echo 'Tag $(TAG) already exists' \
	  exit 1; \
	else \
	  svn cp . $(TAG) $(if $(TAG_MSG),-m '$(TAG_MSG)',); \
	fi

######################################################
# help rules ('make help', 'make help^XXX')
######################################################
help:
	@for myhelp in $(help_TARGETS); do \
	  case $$myhelp in  \
	    cmProject|cmproject|CMProject) \
	      $${PAGER:-less} $(srcdir)/Project_Root/Makefile.README ;; \
	    generic.mk|genericmk|GenericMk) \
	      $(MAKE) -f $(srcdir)/sw/include/generic.mk \
	              PROJECT=$(srcdir) help ;; \
	    *) \
	      echo "Try help^cmProject or help^generic.mk" ;; \
	  esac; \
	done; \

######################################################
# debug rules
######################################################

showVars_LIST = $(patsubst all,$(NAMES),$(showVars_TARGETS))

.PHONY: showVars
showVars:
	$(AT)$(foreach X,$(showVars_LIST), \
	    echo "$(X)_SRC        = $($(X)_SRC)"; \
	    echo "$(X)_ORIG       = $($(X)_ORIG)"; \
	    echo "$(X)_REV        = $($(X)_REV)"; \
	    echo "$(X)_GRAFT      = $($(X)_GRAFT)"; \
	    echo "$(X)_BUILDDIR   = $($(X)_BUILDDIR) ($($(X)_BLDDIR))"; \
	    echo "$(X)_SRC_TYPE   = $($(X)_SRC_TYPE)"; \
	    echo "$(X)_BUILD_TYPE = $($(X)_BUILD_TYPE)"; \
	    echo "$(X)_DEPS       = $($(X)_DEPS)"; \
	    echo "$(X)_MVARS      = $($(X)_MVARS)"; \
	    echo "$(X)_EVARS      = $($(X)_EVARS)"; \
	    echo "$(X)_CARGS      = $($(X)_CARGS)"; \
	    echo "$(X)_DEFCONFIG  = $($(X)_DEFCONFIG)";)

print-%:
	@echo '$* = $($*)'
	@echo '  [$(value $*)] (from $(origin $*))'

######################################################
# Include other modules
######################################################

include $(wildcard $(Project_Root_GRAFT)/modules/*.mk)
