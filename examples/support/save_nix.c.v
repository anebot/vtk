module support

import os

fn rename_atomic(from string, to string) ! { os.rename(from, to)! }
